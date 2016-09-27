# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'fair_cg/version'

Gem::Specification.new do |spec|
  spec.name          = "fair_cg"
  spec.version       = FairCG::VERSION
  spec.authors       = ["Richard Weeks"]
  spec.email         = ["rtweeks21@gmail.com"]
  spec.summary       = "Domain specific language for finite automata."
  spec.homepage      = "https://github.com/rtweeks/fair-cg"
  spec.licenses      = ["GPL-2.0", "GPL-3.0"]
  
  # RDoc
  spec.has_rdoc      = true
  # spec.rdoc_options ↴
  [
    "--title", "FAiR-CG -- Finite Automata in Ruby with Code Generation",
    "--main", 'FairCG::FiniteAutomaton'
  ].each {|a| spec.rdoc_options << a}
  spec.extra_rdoc_files = [
    'license-gpl-2.0.txt',
    'license-gpl-3.0.txt',
  ]

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.5"
  spec.add_development_dependency "rake"
end
