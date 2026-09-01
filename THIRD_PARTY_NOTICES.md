# Artwork and third-party notices

## Omarchief

Omarchy Companion is a fork of [Omarchief](https://github.com/daventhedude/omarchief)
v4.0.0, Copyright (c) 2026 Daven Niemann, distributed under the MIT license
that this repository keeps in [LICENSE](LICENSE). Everything outside
`keystone/Bloub*.{js,qml}` and `pets/bloub/` is that project's work, modified.

## bloub

`keystone/Bloub.js` is a port of [bloub](https://github.com/jeremy-prt/bloub),
Copyright (c) 2026 Jérémy Perret, under the following MIT license.
`keystone/BloubFit.js` is generated from that project's eye-fit solver by
`tools/build-eyefit`.

bloub is an SVG recreation of the x.ai bot avatar. Its silhouettes, easings,
eye geometry and state timings were measured frame by frame off the reference
video, and the port carries those measurements over unaltered — only the
output changed, from SVG path strings to the points and matrices a QML Canvas
takes. `tools/verify-bloub-port` checks that claim against the original rather
than asserting it.

> MIT License
>
> Copyright (c) 2026 Jérémy Perret
>
> Permission is hereby granted, free of charge, to any person obtaining a copy
> of this software and associated documentation files (the "Software"), to deal
> in the Software without restriction, including without limitation the rights
> to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
> copies of the Software, and to permit persons to whom the Software is
> furnished to do so, subject to the following conditions:
>
> The above copyright notice and this permission notice shall be included in all
> copies or substantial portions of the Software.
>
> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
> IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
> FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
> AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
> LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
> OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
> SOFTWARE.

## Omarchy material

Earlier releases of this fork bundled Gritty, original artwork by Daven
Niemann, and Quattro, adapted from
[`themes/tokyo-night/backgrounds/1-quattro.jpg`](https://github.com/basecamp/omarchy/blob/v4.0.0/themes/tokyo-night/backgrounds/1-quattro.jpg)
in Omarchy v4.0.0, Copyright (c) David Heinemeier Hansson. Neither ships any
more — the only companion is drawn — but both remain in this repository's Git
history, which it inherits from Omarchief, under the MIT terms above.

Omarchy Companion is an independent third-party project. Omarchy, x.ai, Grok, Audi,
quattro, Castrol, Michelin, and all other third-party names, logos, and marks
are the property of their respective owners. Their appearance identifies
material already present in the upstream artwork, or the subject bloub set out
to reproduce, and does not imply endorsement. Neither x.ai nor the authors of
Omarchief or bloub are affiliated with this project.
