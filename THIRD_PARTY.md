# Third-party assets

## Lucide icons

The icons in `Heron/Resources/Icons.xcassets` come from [Lucide](https://lucide.dev) (lucide-static 0.544.0),
used under the ISC License:

> Copyright (c) for portions of Lucide are held by Cole Bemis 2013-2023 as part of Feather (MIT).
> All other copyright (c) for Lucide are held by Lucide Contributors 2025.
>
> Permission to use, copy, modify, and/or distribute this software for any purpose with or without fee is
> hereby granted, provided that the above copyright notice and this permission notice appear in all copies.
>
> THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH REGARD TO THIS SOFTWARE
> INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE
> FOR ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS
> OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING
> OUT OF OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

## Citadel (SSH)

Server connections use [Citadel](https://github.com/orlandos-nl/Citadel) by Orlandos, on top of
[SwiftNIO SSH](https://github.com/apple/swift-nio-ssh) and [swift-crypto](https://github.com/apple/swift-crypto)
by Apple. Citadel is used under the MIT License; the Apple packages under the Apache License 2.0. They are
fetched by Swift Package Manager at build time and are not part of this repository.
