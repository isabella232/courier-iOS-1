Pod::Spec.new do |c|
    c.name            = 'CourierMQTT'
    c.version         = '1.4.9'
    c.summary         = "Gojek iOS Long Run Connection Open Source SDK"
    c.description     = "Publish and Subscribe data with bidirectional communication between client and server"
  
    c.homepage        = 'https://github.com/gojek/courier-iOS'
    c.license         = 'MIT'
    c.author          = { "Alfian Losari" => "alfian.losari@gojek.com" }
    c.platform        = :ios, '11.0'
  
    c.source          = {
		:git => "git@github.com:gojek/courier-iOS.git",
		:tag => "0.0.1"
	}
    c.swift_version   = '5.3'
    c.source_files = "CourierMQTT/**/*.{h,m,swift}"

    c.dependency 'CourierCore', "#{c.version}"
    # Make sure to use the forked version from private podspec "ios-ca-podspecs" as it contains critical fix on MQTTSession for transportDidClose
    c.dependency 'MQTTClientGJ', '0.18.2'
    c.dependency 'ReachabilitySwift', '5.0.0'   
end
  