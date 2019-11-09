Pod::Spec.new do |s|
  s.name = 'Benetwork'
  s.version = '1.0.0'
  s.license = 'MIT'
  s.summary = 'A simple networking wrapper with object construction'
  s.homepage = 'https://github.com/davoda/Benetwork'
  s.social_media_url = 'https://twitter.com/NSDavidObject'
  s.authors = { 'David Elsonbaty' => 'dave@elsonbaty.ca' }
  s.source = { :git => 'https://github.com/davoda/Benetwork.git', :tag => s.version }
  s.platforms = { :ios => "11.0", :tvos => "11.0" }
  s.source_files = 'Benetwork/**/*.swift'
  s.requires_arc = true
  s.dependency 'CommonUtilities'
end
