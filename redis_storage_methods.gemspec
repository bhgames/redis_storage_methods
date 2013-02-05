# -*- encoding: utf-8 -*-
require File.expand_path('../lib/redis_storage_methods/version', __FILE__)

Gem::Specification.new do |gem|
  gem.authors       = ["Jordan Prince"]
  gem.email         = ["jordanmprince@gmail.com"]
  gem.description   = %q{Transparently store objects both in redis and your sql store, but GET only on the redis store for speed.}
  gem.summary       = %q{Transparently store objects both in redis and your sql store, but GET only on the redis store for speed.}
  gem.homepage      = ""

  gem.files         = `git ls-files`.split($\)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.name          = "redis_storage_methods"
  gem.require_paths = ["lib"]
  gem.version       = RedisStorageMethods::VERSION
end
