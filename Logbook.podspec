Pod::Spec.new do |s|
  s.name         = "Logbook"
  s.version      = "1.1.0"
  s.summary      = "iOS library for Logbook http://www.logbk.net"
  s.homepage     = "https://www.logbk.net/"
  s.license      = { :type => "Apache License, Version 2.0", :file => "LICENSE" }
  s.author = "pLucky, Inc."
  s.platform     = :ios, "7.0"
  s.source       = { :git => "https://github.com/pLucky-Inc/logbk-ios" }
  s.source_files  = "Logbook", "Logbook/**/*.{h,m}"
  s.frameworks = "Foundation", "UIKit", "SystemConfiguration", "CoreTelephony"
end
