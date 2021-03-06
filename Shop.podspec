#
# Copyright (c) Akos Polster. All rights reserved.
#

Pod::Spec.new do |s|
  s.name = 'Shop'
  s.version = '1.0.0'
  s.summary = 'Simple StoreKit wrapper'
  s.description = <<-DESC
Simple PromiseKit wrapper around StoreKit.
DESC
  s.swift_version = "5"
  s.homepage = 'https://github.com/pipacs/shop'
  s.license = { :type => 'BSD', :file => 'LICENSE' }
  s.author = { 'Akos Polster' => 'akos@pipacs.com' }
  s.source = { :git => 'https://github.com/pipacs/shop.git', :tag => s.version.to_s }
  s.platforms = { :ios => "11.0", :tvos => "11.0" }
  s.source_files = 'Shop/Classes/**/*'
  s.dependency 'KeychainSwift', '~> 16.0'
  s.dependency 'PromiseKit/CorePromise', '~> 6.2'
end
