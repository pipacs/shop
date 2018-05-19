#
# Copyright (c) Akos Polster. All rights reserved.
#

Pod::Spec.new do |s|
  s.name = 'Shop'
  s.version = '0.1.0'
  s.summary = 'Simple StoreKit wrapper'
  s.description = <<-DESC
Simple PromiseKit wrapper around StoreKit.
DESC
  s.homepage = 'https://github.com/pipacs/shop'
  s.license = { :type => 'BSD', :file => 'LICENSE' }
  s.author = { 'Akos Polster' => 'akos@pipacs.com' }
  s.source = { :git => 'https://github.com/pipacs/shop.git', :tag => s.version.to_s }
  s.ios.deployment_target = '10.0'
  s.source_files = 'Shop/Classes/**/*'
  s.dependency 'PromiseKit/CorePromise', '~> 6.2'
  s.dependency 'KeychainSwift', '~> 7.0'
end
