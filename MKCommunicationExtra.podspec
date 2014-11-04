#
# Be sure to run `pod spec lint MKCommunicationExtra.podspec' to ensure this is a
# valid spec and remove all comments before submitting the spec.
#
# To learn more about the attributes see http://docs.cocoapods.org/specification.html
#
Pod::Spec.new do |s|
  s.name         = "MKCommunicationExtra"
  s.version      = "1.0.2"
  s.summary      = "A library which implements the base communication to a Mikrokopter via TCP/IP."
  s.license      = 'MIT'
  s.author       = { "frank" => "frank@frankblumenberg.de" }
  s.homepage     = 'https://github.com/fblumenberg/MKCommunicationExtra'

  s.source       = { :git => "https://github.com/fblumenberg/MKCommunicationExtra.git", :tag => "1.0.1	" }

  s.platform     = :ios, '5.0'
  s.source_files = 'MKCommunicationExtra', 'MKCommunicationExtra/**/*.{h,m,c}'

  s.resources = "MKCommunicationExtra/MKCommunicationExtra/Resources/*"

  s.frameworks = 'CoreGraphics', 'CoreLocation', 'CFNetwork'
  s.requires_arc = false
  s.dependency 'CocoaLumberjack'
end
