---
status: proposed
date: 2026-11-09
---

# Prepare Frontier scout color variants with Segment Anything

Frontier needs multiplayer scouts that players can tell apart at game size. Preserve the scout’s head, hair, neck, and exposed forearms and hands with one protection mask per pose. Hue-rotate the remaining sprite pixels together so the tunic and cape keep their existing color relationship.

Use promptable segmentation on the original sprite pixels. A generative image edit found the right regions on the idle frame, but drifted around their boundaries. After mapping its output back to 512 × 512, 144 of 5,645 selected pixels fell outside the original silhouette, and a sampled left-wrist pixel was missed. Segment Anything predicts a mask in the source image’s coordinate space, which gives us a better starting point for checking the cuff, collar, and hair edges.

## Asset preparation

Start with the Apache 2.0 SAM ViT-B checkpoint exported to ONNX for Transformers.js. Build a small browser tool that accepts a scout PNG, runs the image encoder once, and lets the artist refine selections with positive and negative clicks. Meta’s original browser demo uses a precomputed embedding. The Transformers.js path can encode each uploaded image in the browser. [Browser checkpoint](https://huggingface.co/Xenova/sam-vit-base) · [Transformers.js SAM example](https://huggingface.co/docs/transformers.js/v3.0.0/api/models) · [Meta browser demo](https://github.com/facebookresearch/segment-anything/tree/main/demo)

1. Select the head and neck, then each exposed arm and hand in separate passes. Use negative clicks on the collar, cuffs, and nearby clothing to refine the boundaries.
2. Combine the selections and map them back to the original canvas. Clip the protection mask to the source silhouette. Preview it over the original art with an exaggerated hue shift so leaks onto skin and missed clothing edges are easy to spot.
3. Export the approved mask at the source dimensions for each pose. Record the input asset, checkpoint revision, and prompt coordinates so the selection can be reproduced.
4. Preserve the source alpha when compositing. Use the original colors under the mask and the hue-rotated colors elsewhere. Ship approved PNG variants or masks with the game. Choose a palette deterministically from the session ID and carry the resulting class in cached markup for consistent offline rendering.

Evaluate both idle and walking frames at source size and game size. Check the cuffs, fingers, collar, and hair, and look for color flicker when alternating poses. The shipped game only needs the prepared assets.

## Licensing

Original SAM and SAM 2 release their checkpoints under Apache 2.0, which permits commercial use. The selected browser checkpoint is marked Apache 2.0. Use source artwork we have rights to modify and distribute. The model’s license does not automatically apply to masks or recolored sprites made from that artwork. [Original SAM license](https://github.com/facebookresearch/segment-anything#license) · [SAM 2 license](https://github.com/facebookresearch/sam2#license)

If the authoring tool distributes weights, including a converted ONNX checkpoint served to browsers, include the applicable license and notices and identify modifications. Check the runtime and any third-party model conversion separately. Meta’s training datasets have their own terms. SAM 3 uses custom Meta terms with additional use and redistribution conditions, so review the exact license before replacing the pinned checkpoint. [Apache 2.0 redistribution terms](https://www.apache.org/licenses/LICENSE-2.0#redistribution) · [SAM 3 license](https://github.com/facebookresearch/sam3/blob/main/LICENSE)
