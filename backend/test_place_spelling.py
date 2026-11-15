"""Scripted SDK tests for misheard place-name repair; no real model inference."""
import json, unittest
from unittest.mock import patch
from openai.types.responses import ResponseOutputMessage, ResponseOutputText
from agents import ModelResponse
from agents.usage import Usage
import app as service
import test_backend as fixtures

class PlaceModel(fixtures.ScriptedModel):
    def __init__(self, name='Louis Armstrong', confident=True):
        super().__init__(); self.name = name; self.confident = confident
    async def get_response(self, *args, **kwargs):
        self.inputs.append(kwargs.get('input', args[1] if len(args)>1 else []))
        output = [ResponseOutputMessage(type='message', role='assistant', id='msg', status='completed', content=[
            ResponseOutputText(type='output_text', text=json.dumps({'name': self.name, 'confident': self.confident}), annotations=[])])]
        return ModelResponse(output=output, usage=Usage(), response_id='offline-place-scripted')

class PlaceSpellingTests(unittest.TestCase):
    setUp = fixtures.BridgeTests.setUp
    def ask(self, fake, heard='louis rm strng', **extra):
        original = service.place_agent
        def agent():
            value = original(); value.model = fake; return value
        context = dict(self.context, knownDestinations=[{'name': 'Friend Center'}])
        with patch.object(service, 'place_agent', agent):
            return self.client.post('/agent/turn', headers=self.headers, json={'mode': 'place', 'utterance': heard, 'context': context, **extra})
    def test_misheard_name_is_repaired_without_tools(self):
        fake = PlaceModel()
        self.assertEqual(service.place_agent().tools, [])
        response = self.ask(fake)
        self.assertEqual(response.status_code, 200, response.text)
        self.assertIsNone(response.json()['call'])
        self.assertEqual(response.json()['final'], {'kind': 'place', 'answer': 'Louis Armstrong', 'responseCallId': None, 'clarification': 'none'})
        sent = json.dumps(fake.inputs)
        self.assertIn('louis rm strng', sent); self.assertIn('Friend Center', sent)
        self.assertNotIn('sessionRevision', sent)
        self.assertFalse(service.runs)
    def test_unsure_answer_is_not_used(self):
        response = self.ask(PlaceModel('Somewhere', confident=False))
        self.assertEqual(response.status_code, 200)
        self.assertIsNone(response.json()['final']['answer'])
    def test_place_mode_rejects_history(self):
        response = self.ask(PlaceModel(), history=[{'role': 'user', 'content': 'hi'}, {'role': 'assistant', 'content': 'hello'}])
        self.assertEqual(response.status_code, 422)

if __name__ == '__main__': unittest.main()
