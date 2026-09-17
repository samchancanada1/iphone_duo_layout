#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint iphone_duo_layout.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'iphone_duo_layout'
  s.version          = '0.1.0'
  s.summary          = 'Native iPhone Duo layout adaptation for Flutter: reserved regions, hinge updates, adaptive layouts and system toolbars.'
  s.description      = <<-DESC
Native iPhone Duo layout adaptation for Flutter: reserved regions, hinge updates, adaptive layouts and system toolbars.
                       DESC
  s.homepage         = 'https://github.com/samchancanada1/iphone_duo_layout'
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = 'samchancanada1'
  s.source           = { :path => '.' }
  s.source_files = 'iphone_duo_layout/Sources/iphone_duo_layout/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  # If your plugin requires a privacy manifest, for example if it uses any
  # required reason APIs, update the PrivacyInfo.xcprivacy file to describe your
  # plugin's privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'iphone_duo_layout_privacy' => ['iphone_duo_layout/Sources/iphone_duo_layout/PrivacyInfo.xcprivacy']}
end
