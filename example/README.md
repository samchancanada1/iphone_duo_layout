# iPhone Duo Layout example

Shows native capability status. When an API query succeeds, draws real active
regions over the Flutter host view: orange for division, purple for occlusion.
Native API access is enabled by default; build with the SDK that provides it.
Older iOS versions return `osUnavailable`. No SDK compilation flag is required.
No fake hinge, camera cutout, or device detection is used.
Dart analysis and widget tests pass; native new-SDK compilation and device validation remain pending.
