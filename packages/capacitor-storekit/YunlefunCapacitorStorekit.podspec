require 'json'

package = JSON.parse(File.read(File.join(__dir__, 'package.json')))

Pod::Spec.new do |s|
  s.name = 'YunlefunCapacitorStorekit'
  s.version = package['version']
  s.summary = package['description']
  s.license = package['license']
  s.homepage = 'https://github.com/YunLeFun'
  s.author = 'YunLeFun'
  s.source = { :git => 'https://github.com/YunLeFun/apps.yunle.fun.git', :tag => s.version.to_s }
  s.source_files = 'ios/Plugin/**/*.{swift,h,m}'
  s.ios.deployment_target = '16.0'
  s.dependency 'Capacitor'
  s.swift_version = '5.9'
end
