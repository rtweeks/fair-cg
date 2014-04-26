require 'rake'
require 'yaml'

Gem::Specification.new do |spec|
  spec.name = "fair-cg"
  spec.version = YAML.load_file(File.join(File.dirname(__FILE__), "gem-version.yaml")).join('.')
  spec.summary = "Domain specific language for finite automata."
  spec.homepage = "http://fair-cg.rubyforge.org/"
  spec.authors = ["Richard T. Weeks"]
  spec.files = FileList['**/*.rb'].to_a
  spec.require_paths = ['.']
  spec.has_rdoc = true
  spec.rdoc_options << "--title" << "FAiR-CG -- Finite Automata in Ruby with Code Generation" <<
    "--main" << 'FairCG::FiniteAutomaton'
  spec.extra_rdoc_files = [
    'license-gpl-2.0.txt',
    'license-gpl-3.0.txt',
  ]
  spec.rubyforge_project = "fair-cg"
end
