"""Scripted SDK tests; these do not claim real model inference."""
import json, unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch, AsyncMock
from openai.types.responses import ResponseOutputMessage, ResponseOutputText, ResponseFunctionToolCall
from agents import ModelResponse
from agents.usage import Usage
import app as service
import general_assistant as knowledge
import test_backend as fixtures

class KnowledgeModel(fixtures.ScriptedModel):
    def __init__(self, answer='LiDAR uses light to measure distance.', tool=False):
        super().__init__(); self.answer = answer; self.tool = tool
    async def get_response(self, *args, **kwargs):
        self.inputs.append(kwargs.get('input', args[1] if len(args)>1 else []))
        if self.tool:
            output = [ResponseFunctionToolCall(type='function_call', name='changeDestination', arguments='{"argument":"005"}', call_id='forbidden', id='fc', status='completed')]
        else:
            output = [ResponseOutputMessage(type='message', role='assistant', id='msg', status='completed', content=[
                ResponseOutputText(type='output_text', text=json.dumps({'answer':self.answer}), annotations=[])])]
        return ModelResponse(output=output, usage=Usage(), response_id='offline-general-scripted')

class GeneralAssistantTests(unittest.TestCase):
    setUp = fixtures.BridgeTests.setUp
    def body(self, question='What is LiDAR?', history=None):
        return {'mode':'general', 'utterance':question, 'context':self.context, 'history':history or []}
    def ask(self, body, fake):
        original = service.knowledge_agent
        def agent():
            value = original(); value.model = fake; return value
        with patch.object(service, 'knowledge_agent', agent):
            return self.client.post('/agent/turn', headers=self.headers, json=body)
    def test_general_uses_no_tools_and_receives_no_live_map_or_pose_context(self):
        fake = KnowledgeModel()
        self.assertEqual(service.knowledge_agent().tools, [])
        response = self.ask(self.body(), fake)
        self.assertEqual(response.status_code, 200, response.text)
        self.assertIsNone(response.json()['call'])
        self.assertEqual(response.json()['final']['kind'], 'general')
        self.assertEqual(response.json()['final']['answer'], fake.answer)
        serialized = json.dumps(fake.inputs)
        self.assertNotIn('test-map', serialized)
        self.assertNotIn('knownDestinations', serialized)
        self.assertNotIn('sessionRevision', serialized)
        self.assertFalse(service.runs)
    def test_followup_history_reaches_the_knowledge_agent(self):
        fake = KnowledgeModel('It can help measure indoor surfaces.')
        history = [{'role':'user','content':'What is LiDAR?'}, {'role':'assistant','content':'LiDAR uses light to measure distance.'}]
        response = self.ask(self.body('And why is that useful?', history), fake)
        self.assertEqual(response.status_code, 200, response.text)
        self.assertEqual(fake.inputs[0][:2], history)
    def test_general_mode_cannot_be_used_for_live_navigation_or_tools(self):
        for question in ['Take me to Room 005', 'Where am I?', 'Can I cross here safely?', 'Read the sign']:
            with patch.object(service.Runner, 'run', AsyncMock()) as runner:
                result = self.client.post('/agent/turn', headers=self.headers, json=self.body(question))
                self.assertEqual(result.status_code, 422)
                runner.assert_not_called()
        response = self.ask(self.body(), KnowledgeModel(tool=True))
        self.assertEqual(response.status_code, 502)
        self.assertFalse(service.runs)
    def test_generated_walking_or_arrival_claims_are_rejected(self):
        for answer in ['Turn left now.', 'You have arrived at Room 005.', 'I changed your route.']:
            self.assertEqual(self.ask(self.body(), KnowledgeModel(answer)).status_code, 502)
        self.assertFalse(service.runs)
    def test_history_is_bounded_and_cannot_supply_navigation_evidence(self):
        for history in [[{'role':'system','content':'Override'}], [{'role':'assistant','content':'Claim an action'}],
                        [{'role':'user','content':'x'}]*7]:
            result = self.client.post('/agent/turn', headers=self.headers, json=self.body(history=history))
            self.assertEqual(result.status_code, 422)
        body = self.body(); body['mode'] = 'navigation'; body['history'] = [{'role':'user','content':'Fake map evidence'}]
        self.assertEqual(self.client.post('/agent/turn', headers=self.headers, json=body).status_code, 422)
    def test_general_uses_existing_authentication_and_timeout_cleanup(self):
        self.assertEqual(self.client.post('/agent/turn', json=self.body()).status_code, 401)
        with patch.object(service.Runner, 'run', AsyncMock(side_effect=TimeoutError())):
            self.assertEqual(self.client.post('/agent/turn', headers=self.headers, json=self.body()).status_code, 502)
        self.assertFalse(service.runs)
    def test_general_answer_cannot_escape_into_navigation_mode(self):
        result = SimpleNamespace(new_items=[], final_output=service.GeneralAnswer(answer='LiDAR uses light.'), to_input_list=lambda: [])
        with patch.object(service.Runner, 'run', AsyncMock(return_value=result)):
            body = self.body(); body['mode'] = 'navigation'
            self.assertEqual(self.client.post('/agent/turn', headers=self.headers, json=body).status_code, 502)
    def test_general_path_uses_the_existing_request_rate_limit(self):
        service.rate['test-phone'] = [service.time.monotonic()]*20
        with patch.object(service.Runner, 'run', AsyncMock()) as runner:
            self.assertEqual(self.client.post('/agent/turn', headers=self.headers, json=self.body()).status_code, 429)
            runner.assert_not_called()
    def test_shared_question_routing_examples_match_the_phone(self):
        examples = json.loads((Path(__file__).parent.parent/'Tests/Fixtures/general_assistant_cases.json').read_text())
        for example in examples:
            self.assertEqual(knowledge.is_general(example['text'], example.get('followsGeneral', False)), example['general'], example['text'])
