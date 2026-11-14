"""Offline SDK integration tests. Scripted model outputs are explicitly NOT real inference."""
import json, os, time, unittest, pathlib, subprocess
from unittest.mock import patch
import jwt
from fastapi.testclient import TestClient
from agents import Model, ModelResponse
from agents.usage import Usage
from openai.types.responses import ResponseFunctionToolCall, ResponseOutputMessage, ResponseOutputText
import app as service

class ScriptedModel(Model):
    def __init__(self): self.inputs = []; self.index = 0
    async def get_response(self, *args, **kwargs):
        inputs = kwargs.get('input', args[1] if len(args)>1 else [])
        self.inputs.append(inputs)
        self.index += 1
        if self.index == 1:
            output = [ResponseFunctionToolCall(type='function_call', name='resolveDestination', arguments='{"argument":"Room 105"}', call_id='call_actual_1', id='fc_1', status='completed')]
        else:
            output = [ResponseOutputMessage(type='message', role='assistant', id='msg_1', status='completed', content=[ResponseOutputText(type='output_text', text='{"responseCallId":"call_actual_1","clarification":"none"}', annotations=[])])]
        return ModelResponse(output=output, usage=Usage(), response_id='offline-scripted')
    async def stream_response(self, *args, **kwargs):
        raise NotImplementedError()
        yield

class ScriptedRoutingModel(ScriptedModel):
    async def get_response(self, *args, **kwargs):
        inputs = kwargs.get('input', args[1] if len(args)>1 else [])
        self.inputs.append(inputs); self.index += 1
        if self.index <= 3:
            argument = 'Room 105'
            if self.index > 1:
                results = [json.loads(i['output']) for i in inputs if isinstance(i,dict) and i.get('type')=='function_call_output']
                argument = results[-1]['data']['destinationId']
            name = ['resolveDestination','calculateAccessibleRoute','changeDestination'][self.index-1]
            output = [ResponseFunctionToolCall(type='function_call',name=name,arguments=json.dumps({'argument':argument}),call_id='routing_'+str(self.index),id='fc_'+str(self.index),status='completed')]
        else:
            output = [ResponseOutputMessage(type='message',role='assistant',id='msg',status='completed',content=[ResponseOutputText(type='output_text',text='{"responseCallId":"routing_3","clarification":"none"}',annotations=[])])]
        return ModelResponse(output=output,usage=Usage(),response_id='offline-scripted-routing')

class BridgeTests(unittest.TestCase):
    def setUp(self):
        self.env = patch.dict(os.environ, {'AGENT_AUTH_SECRET':'x'*40, 'OPENAI_API_KEY':'offline-test-placeholder'})
        self.env.start(); self.addCleanup(self.env.stop)
        service.runs.clear(); service.rate.clear()
        now = int(time.time())
        self.token = jwt.encode({'sub':'test-phone','iat':now,'exp':now+300,'iss':'indoorbility-dev','aud':'indoorbility'}, 'x'*40, algorithm='HS256')
        self.headers = {'Authorization':'Bearer '+self.token}
        self.context = {'sessionId':'session-1','sessionRevision':2,'buildingId':'test-map','floor':0,'tracking':'verified','destinationId':'106','avoidStairs':True,'instruction':'Continue','knownDestinations':[],'knownClosures':[]}
        self.client = TestClient(service.app)
    def test_route_tools_require_device_evidence_and_exact_target(self):
        run = service.Pending('phone', 'session-1', [], time.monotonic()+100)
        context = service.Context(**self.context)
        def tools(): return {t.name: t for t in service.prepared_coordinator(run, context).tools}
        self.assertNotIn('calculateAccessibleRoute', tools())
        self.assertNotIn('changeDestination', tools())
        run.call = {'tool':'resolveDestination'}
        result = service.ToolResult(callId='resolved', sessionRevision=2, status='success', data={'destinationId':'actual-device-id'}, userSafeExplanation='Resolved')
        service.accept_route_evidence(run, result, context)
        self.assertEqual(tools()['calculateAccessibleRoute'].params_json_schema['properties']['argument']['enum'], ['actual-device-id'])
        self.assertNotIn('changeDestination', tools())
        run.call = {'tool':'calculateAccessibleRoute'}
        service.accept_route_evidence(run, result, context)
        self.assertIn('changeDestination', tools())
        context.sessionRevision += 1
        self.assertNotIn('changeDestination', tools())
        self.assertNotIn('calculateAccessibleRoute', tools())

    def test_failed_resolution_and_calculation_do_not_unlock_actions(self):
        run = service.Pending('phone', 'session-1', [], time.monotonic()+100, resolved='old', calculated='old', route_revision=2)
        context = service.Context(**self.context)
        run.call = {'tool':'resolveDestination'}
        result = service.ToolResult(callId='failed', sessionRevision=2, status='unavailable', data={'destinationId':'old'}, userSafeExplanation='Unknown room')
        service.accept_route_evidence(run, result, context)
        self.assertIsNone(run.resolved)
        self.assertIsNone(run.calculated)
        run.resolved = 'actual'; run.call = {'tool':'calculateAccessibleRoute'}
        result.status = 'success'; result.data = {'destinationId':'wrong'}
        service.accept_route_evidence(run, result, context)
        self.assertIsNone(run.calculated)

    def test_connection_check_requires_auth_and_only_returns_status(self):
        self.assertEqual(self.client.get("/agent/check").status_code, 401)
        response = self.client.get("/agent/check", headers=self.headers)
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json(), {"authenticated": True, "modelConfigured": True})

    def test_authentication_required(self):
        self.assertEqual(self.client.post('/agent/turn',json={'utterance':'hello','context':self.context}).status_code,401)
    def test_expired_token_rejected(self):
        token = jwt.encode({'sub':'x','iat':1,'exp':2,'iss':'indoorbility-dev','aud':'indoorbility'}, 'x'*40, algorithm='HS256')
        self.assertEqual(self.client.post('/agent/turn',headers={'Authorization':'Bearer '+token},json={'utterance':'hello','context':self.context}).status_code,401)
    def test_no_credential_is_truthful(self):
        with patch.dict(os.environ, {'OPENAI_API_KEY':''}):
            self.assertEqual(self.client.post('/agent/turn',headers=self.headers,json={'utterance':'hello','context':self.context}).status_code,503)
    def test_unknown_request_fields_rejected(self):
        self.assertEqual(self.client.post('/agent/turn',headers=self.headers,json={'utterance':'hello','context':self.context,'inventedPose':True}).status_code,422)
    def test_size_limit(self):
        self.assertEqual(self.client.post('/agent/turn',content='x'*33000,headers=self.headers).status_code,413)
    def test_sdk_proposal_waits_for_device_result(self):
        fake = ScriptedModel(); original = service.coordinator
        def agent():
            a = original(); a.model = fake; return a
        with patch.object(service,'coordinator',agent):
            first = self.client.post('/agent/turn',headers=self.headers,json={'utterance':'Room 105 instead','context':self.context})
            self.assertEqual(first.status_code,200,first.text)
            reply = first.json(); self.assertEqual(reply['call']['tool'],'resolveDestination')
            self.assertEqual(reply['call']['expectedRevision'],2)
            # No device output -> cannot resume or claim successful execution.
            invalid = self.client.post('/agent/turn',headers=self.headers,json={'context':self.context,'runId':reply['runId']})
            self.assertEqual(invalid.status_code,409)
            actual = {'callId':'call_actual_1','sessionRevision':2,'status':'unavailable','data':{},'userSafeExplanation':'Room unknown'}
            second = self.client.post('/agent/turn',headers=self.headers,json={'context':self.context,'runId':reply['runId'],'result':actual})
            self.assertEqual(second.status_code,200,second.text)
            rendered = json.dumps(fake.inputs[-1])
            self.assertIn('Room unknown',rendered)
            self.assertNotIn('pending_device_execution',rendered)
            self.assertEqual(second.json()['final']['responseCallId'],'call_actual_1')
    def test_provider_failure_returns_error_without_success(self):
        from unittest.mock import AsyncMock
        with patch.object(service.Runner, 'run', AsyncMock(side_effect=TimeoutError())):
            result = self.client.post('/agent/turn',headers=self.headers,json={'utterance':'Room 105','context':self.context})
        self.assertEqual(result.status_code,502)
        self.assertEqual(len(service.runs),0)
    def test_wrong_result_revision_does_not_resume(self):
        service.runs['run'] = service.Pending('test-phone','session-1',[],time.monotonic()+100,call={'callId':'call'})
        result = self.client.post('/agent/turn',headers=self.headers,json={'context':self.context,'runId':'run',
            'result':{'callId':'call','sessionRevision':999,'status':'success','data':{},'userSafeExplanation':'invented'}})
        self.assertEqual(result.status_code,409)
    def test_scripted_sdk_calls_execute_real_swift_routing(self):
        binary = pathlib.Path(__file__).resolve().parent.parent / '.build/debug/IndoorbilityAgentProbe'
        self.assertTrue(binary.exists(), 'Build swift build --product IndoorbilityAgentProbe before this integration test')
        process = subprocess.Popen([str(binary)],stdin=subprocess.PIPE,stdout=subprocess.PIPE,text=True)
        try:
            context = json.loads(process.stdout.readline())['context']
            model = ScriptedRoutingModel(); original = service.coordinator
            def agent():
                a = original(); a.model = model; return a
            body = {'utterance':'Room 105 instead','context':context}
            with patch.object(service,'coordinator',agent):
                for _ in range(3):
                    response = self.client.post('/agent/turn',headers=self.headers,json=body)
                    self.assertEqual(response.status_code,200,response.text)
                    reply = response.json()
                    process.stdin.write(json.dumps(reply['call'])+'\n'); process.stdin.flush()
                    actual = json.loads(process.stdout.readline())
                    self.assertNotIn('error',actual)
                    body = {'runId':reply['runId'],'context':actual['context'],'result':actual['result']}
                self.assertTrue(actual['destinationChanged'])
                self.assertTrue(actual['positionPreserved'])
                self.assertAlmostEqual(actual['remaining'],2)
                final = self.client.post('/agent/turn',headers=self.headers,json=body)
                self.assertEqual(final.status_code,200,final.text)
                self.assertEqual(final.json()['final']['responseCallId'],'routing_3')
        finally:
            process.terminate(); process.wait(timeout=5)
            process.stdin.close(); process.stdout.close()
    def test_run_owned_by_phone(self):
        service.runs['secret-run'] = service.Pending('another-phone','session-1',[],time.monotonic()+100)
        result = self.client.post('/agent/turn',headers=self.headers,json={'context':self.context,'runId':'secret-run'})
        self.assertEqual(result.status_code,404)

if __name__ == '__main__': unittest.main(verbosity=2)
