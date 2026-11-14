"""Real OpenAI calls + real Swift tools with explicitly synthetic pose; no fake responses."""
import json, os, pathlib, subprocess, time, secrets
import httpx, jwt
from dotenv import load_dotenv
root = pathlib.Path(__file__).resolve().parent.parent
load_dotenv(root/'backend/.env', override=False)
base = os.environ.get('AGENT_TEST_URL', 'http://127.0.0.1:8765')
token = os.environ.get('AGENT_TEST_TOKEN')
if not token:
    secret = os.environ.get('AGENT_AUTH_SECRET','')
    if len(secret)<32: raise SystemExit('Configure AGENT_AUTH_SECRET in backend/.env.')
    now=int(time.time())
    token=jwt.encode({'sub':'probe-'+secrets.token_hex(8),'iat':now,'exp':now+300,'iss':'indoorbility-dev','aud':'indoorbility'},secret,algorithm='HS256')
probe = subprocess.Popen([str(root/'.build/debug/IndoorbilityAgentProbe')], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
try:
    current = json.loads(probe.stdout.readline()); trace=[]; outcomes=[]
    with httpx.Client(timeout=30, follow_redirects=False, trust_env=False) as client:
        for utterance, target in [('Take me to Room 106.','Room 106'),('Actually, Room 105 instead.','Room 105'),("What's in front of me?",None)]:
            body={'utterance':utterance,'context':current['context']}; executed=[]
            for _ in range(5):
                response=client.post(base+'/agent/turn',headers={'Authorization':'Bearer '+token},json=body)
                if response.status_code!=200: raise RuntimeError(f'Backend returned HTTP {response.status_code}; inspect sanitized server logs.')
                reply=response.json()
                if reply.get('call'):
                    call=reply['call']; probe.stdin.write(json.dumps(call)+'\n');probe.stdin.flush()
                    current=json.loads(probe.stdout.readline())
                    if 'error' in current:
                        print(json.dumps({'failedTool': call['tool'], 'argument': call['argument'], 'priorExecution': trace, 'error': current['error']}), flush=True)
                        raise RuntimeError(current['error'])
                    actual=current['result'];executed.append(call['tool'])
                    trace.append({'runId':reply['runId'],'tool':call['tool'],'callId':call['callId'],'status':actual['status'],'revision':actual['sessionRevision'],'result':actual['userSafeExplanation']})
                    body={'runId':reply['runId'],'context':current['context'],'result':actual}
                else: break
            if target:
                assert current.get('destinationLabel')==target and current.get('positionPreserved'), 'Destination/position assertion failed'
                assert 'changeDestination' in executed, 'Model did not execute route activation'
            else:
                assert 'describeCurrentView' in executed, 'Model did not request camera observation'
                assert current['result']['status']=='unavailable', 'Probe must not fabricate camera evidence'
            outcomes.append({'request':utterance,'destination':current.get('destinationLabel'),'remainingMetres':current.get('remaining'),'posePreserved':current.get('positionPreserved')})
    print(json.dumps({'modelInvocation':'real','pose':'synthetic','ARKitTested':False,'cameraTested':False,'outcomes':outcomes,'trace':trace},indent=2))
finally:
    probe.terminate();probe.wait(timeout=5)
