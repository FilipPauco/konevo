# Third-party notices

Konevo contains third-party software. Konevo's source-available license applies
only to Konevo-authored code and assets; third-party components remain subject
to their own licenses. If a component's license conflicts with Konevo's license
notice, the component's license controls for that component.

This notice covers the dependencies locked in `mix.lock` and
`assets/package-lock.json` as of 2026-08-31. Update it whenever either lockfile
changes, and preserve any additional upstream `NOTICE` files.

## JavaScript components bundled into Konevo assets

| Component family | Locked version | License |
| --- | --- | --- |
| `@popperjs/core` | 2.11.8 | MIT |
| `@tiptap/*` | 3.26.1 | MIT |
| `flatpickr` | 4.6.13 | MIT |
| `flyonui` | 2.4.1 | MIT; includes notices for daisyUI and Preline |
| `fullcalendar` and `@fullcalendar/*` | 7.0.0 | MIT |
| `highlight.js` | 11.11.1 | BSD 3-Clause |
| `live_select` | local package from `deps/live_select` | Apache-2.0 |
| `lodash` | 4.18.1 | MIT |
| `lowlight`, `linkifyjs`, and ProseMirror packages | versions in `assets/package-lock.json` | MIT |
| `sortablejs` | 1.15.7 | MIT |
| `temporal-polyfill` and supporting packages | versions in `assets/package-lock.json` | MIT and Apache-2.0 |

The complete JavaScript dependency and transitive-dependency inventory is
`assets/package-lock.json`. No ApexCharts code is included.

## Elixir and Erlang runtime components

The full, exact dependency inventory is `mix.lock`. Direct runtime components
include Phoenix, Ecto, Postgrex, Oban, Req, Swoosh, Bandit, Gettext, Jason,
LangChain, LiveSelect, Mogrify, DNSCluster, Telemetry, and their transitive
dependencies.

The direct dependencies use the following license families:

- Apache-2.0: Ecto SQL, Postgrex, Oban, Req, Gettext, Jason, LiveSelect,
  LangChain, Dotenvy, NimbleTOTP, Telemetry Metrics, and Telemetry Poller.
- MIT: Phoenix and its web packages, Bandit, Bodyguard, EQrcode, Swoosh, Mail,
  Mogrify, DNSCluster, Slugy, and related packages.
- BSD 3-Clause: PBKDF2 Elixir.

Package-specific copyright notices and any additional notice files remain part
of the relevant upstream package. Their current package sources are available
from [Hex](https://hex.pm/) and npm, using the versions locked above.

## License texts

### MIT License

Copyright (c) the respective copyright holders and contributors.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

### Apache License 2.0

Licensed under the Apache License, Version 2.0 (the "License"); you may not
use these components except in compliance with the License. You may obtain a
copy of the License at <https://www.apache.org/licenses/LICENSE-2.0>.

Unless required by applicable law or agreed to in writing, software distributed
under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
CONDITIONS OF ANY KIND, either express or implied. See the License for the
specific language governing permissions and limitations under the License.

### BSD 3-Clause License

Copyright (c) the respective copyright holders and contributors.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.
3. Neither the name of the copyright holder nor the names of its contributors
   may be used to endorse or promote products derived from this software without
   specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
