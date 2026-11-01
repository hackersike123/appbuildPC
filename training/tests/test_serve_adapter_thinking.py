"""Regression test for local Qwen3.5 adapter chat-template settings."""

import sys
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock

import torch

ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

import training.serve_adapter as serve_adapter


class FakeBatch(dict):
    def to(self, device):
        return self


class ServeAdapterThinkingTests(unittest.TestCase):
    def setUp(self):
        self.original_model = serve_adapter.model
        self.original_processor = serve_adapter.processor

        self.processor = Mock()
        self.processor.apply_chat_template.return_value = FakeBatch(
            {"input_ids": torch.tensor([[1]], dtype=torch.long)}
        )
        self.processor.tokenizer = SimpleNamespace(pad_token_id=0, eos_token_id=0)
        self.processor.decode.return_value = "Safe PC answer"

        self.model = Mock()
        self.model.get_input_embeddings.return_value.weight = SimpleNamespace(
            device=torch.device("cpu")
        )
        self.model.generate.return_value = torch.tensor([[1, 2]], dtype=torch.long)

        serve_adapter.model = self.model
        serve_adapter.processor = self.processor

    def tearDown(self):
        serve_adapter.model = self.original_model
        serve_adapter.processor = self.original_processor

    def test_local_chat_template_disables_qwen_thinking(self):
        result = serve_adapter.chat_completions(
            {"messages": [{"role": "user", "content": "Summarize this PC build."}]}
        )

        self.assertEqual(
            result["choices"][0]["message"]["content"], "Safe PC answer"
        )
        kwargs = self.processor.apply_chat_template.call_args.kwargs
        self.assertIn("enable_thinking", kwargs)
        self.assertFalse(kwargs["enable_thinking"])

    def test_greedy_generation_omits_sampling_only_arguments(self):
        serve_adapter.chat_completions(
            {
                "messages": [{"role": "user", "content": "Summarize this PC build."}],
                "temperature": 0,
            }
        )

        generation = self.model.generate.call_args.kwargs
        self.assertFalse(generation["do_sample"])
        for key in ("temperature", "top_p", "top_k"):
            self.assertNotIn(key, generation)


if __name__ == "__main__":
    unittest.main()
