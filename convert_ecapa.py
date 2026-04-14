#!/usr/bin/env python3
"""
Convert SpeechBrain ECAPA-TDNN to CoreML for on-device speaker verification.

Requirements:
    pip install speechbrain coremltools torch torchaudio numpy

Usage:
    python3 convert_ecapa.py

Output:
    ECAPA_TDNN.mlpackage  — drag this into the Xcode project (target membership: Aham)

Model contract (must match SpeakerEmbedding.swift):
    Input:  "fbank_features"   shape [1, 300, 80]  float32  (batch, time, mel-bins)
    Output: "speaker_embedding" shape [1, 192]      float32  (L2-normalized)
"""

import torch
import torch.nn.functional as F

# ── 1. Load pretrained ECAPA-TDNN ──────────────────────────────────────────────

print("Loading speechbrain/spkrec-ecapa-voxceleb …")

try:
    from speechbrain.inference.classifiers import EncoderClassifier
except ImportError:
    # older SpeechBrain API
    from speechbrain.pretrained import EncoderClassifier

classifier = EncoderClassifier.from_hparams(
    source="speechbrain/spkrec-ecapa-voxceleb",
    savedir="pretrained_models/spkrec-ecapa-voxceleb",
    run_opts={"device": "cpu"},
)
embedding_model = classifier.mods["embedding_model"]
embedding_model.eval()

# ── 2. Wrapper: [1, T=300, C=80] → [1, 192] L2-normalised ────────────────────

class EmbeddingWrapper(torch.nn.Module):
    """
    SpeechBrain ECAPA_TDNN.forward() accepts [B, T, C] directly.
    We add L2-normalization so the output is ready for cosine similarity.
    """
    def __init__(self, model):
        super().__init__()
        self.model = model

    def forward(self, fbank: torch.Tensor) -> torch.Tensor:
        # fbank: [1, 300, 80]
        emb = self.model(fbank)                        # → [1, 1, 192] or [1, 192]
        if emb.dim() == 3:
            emb = emb.squeeze(1)                       # → [1, 192]
        return F.normalize(emb, p=2, dim=1)            # L2-normalize

wrapper = EmbeddingWrapper(embedding_model)
wrapper.eval()

# ── 3. Trace ───────────────────────────────────────────────────────────────────

T_FRAMES   = 300   # 3 s @ 10 ms hop
MEL_BINS   = 80

dummy = torch.randn(1, T_FRAMES, MEL_BINS)

print(f"Tracing with input shape {list(dummy.shape)} …")
with torch.no_grad():
    traced = torch.jit.trace(wrapper, dummy)
    out    = traced(dummy)

print(f"Output shape: {list(out.shape)}")
assert out.shape == (1, 192), f"Unexpected output shape: {out.shape}"

# ── 4. Convert to CoreML ───────────────────────────────────────────────────────

import coremltools as ct

print("Converting to CoreML (this may take a minute) …")
mlmodel = ct.convert(
    traced,
    inputs=[
        ct.TensorType(
            name="fbank_features",
            shape=(1, T_FRAMES, MEL_BINS),
            dtype=float,
        )
    ],
    outputs=[
        ct.TensorType(name="speaker_embedding", dtype=float)
    ],
    minimum_deployment_target=ct.target.macOS13,
    compute_precision=ct.precision.FLOAT32,
)

# ── 5. Save ────────────────────────────────────────────────────────────────────

output_path = "ECAPA_TDNN.mlpackage"
mlmodel.save(output_path)

print(f"\n✅  Saved to {output_path}")
print("Next steps:")
print("  1. In Xcode: drag ECAPA_TDNN.mlpackage into the project navigator")
print("  2. Make sure target membership 'Aham' is checked")
print("  3. Build — speaker verification will automatically use the neural model")
