# Test assets

`sample_photo.jpg` is a 256x256 baseline JPEG generated synthetically for this
repository: a smooth two-axis gradient with a radial lobe and mild grain, so the
native encoder has real low-frequency content to work with. It is not derived
from any third-party photograph, so it carries no attribution requirement and is
covered by this repository's BSD 3-Clause license.

It is used by `example/integration_test/compression_test.dart`. Keep it small;
it ships inside the example app bundle.

`sample_wide.jpg` is a 400x200 JPEG gradient generated synthetically (ffmpeg
`gradients` source), so it is also free of third-party attribution. Its 2:1
aspect ratio lets the resize integration tests tell a proportional scale from
a square crop or stretch.
