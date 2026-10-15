# Third-party assets

## Tabler Icons

The icons in `Heron/Resources/Icons.xcassets` come from [Tabler Icons](https://tabler.io/icons) (@tabler/icons 3.31.0),
used under the MIT License:

> Copyright (c) 2020-2024 Paweł Kuna
>
> Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated
> documentation files (the "Software"), to deal in the Software without restriction, including without limitation
> the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and
> to permit persons to whom the Software is furnished to do so, subject to the following conditions:
>
> The above copyright notice and this permission notice shall be included in all copies or substantial portions
> of the Software.
>
> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED
> TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
> THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF
> CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
> DEALINGS IN THE SOFTWARE.

## Citadel (SSH)

Server connections use [Citadel](https://github.com/orlandos-nl/Citadel) by Orlandos, on top of
[SwiftNIO SSH](https://github.com/apple/swift-nio-ssh) and [swift-crypto](https://github.com/apple/swift-crypto)
by Apple. Citadel is used under the MIT License; the Apple packages under the Apache License 2.0. They are
fetched by Swift Package Manager at build time and are not part of this repository.
