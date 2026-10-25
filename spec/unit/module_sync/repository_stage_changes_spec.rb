# frozen_string_literal: true

require 'spec_helper'

describe ModuleSync::Repository, '#stage_changes' do
  subject(:repository) { described_class.new(directory: directory, remote: 'https://github.com/example/repository.git') }

  let(:directory) { Dir.mktmpdir }
  let(:git) { instance_double(Git::Base) }

  def create_script(content)
    File.write(File.join(directory, 'autofix'), "#!/bin/sh\n#{content}\n")
    File.chmod(0o755, File.join(directory, 'autofix'))
  end

  def stage_changes(script = 'autofix')
    repository.stage_changes(['README.md'], pre_commit_script: script, configs: directory)
  end

  before { repository.instance_variable_set(:@git, git) }

  after { FileUtils.remove_entry(directory) }

  it 'runs the pre-commit script in the module before staging the whole working tree' do
    create_script('echo "$PWD $1" > output')
    script_output = nil
    allow(git).to receive(:add).with(all: true) { script_output = File.read(File.join(directory, 'output')) }

    stage_changes

    expect(script_output).to eq "#{directory} #{directory}\n"
  end

  it 'runs the pre-commit script without the Bundler environment of msync' do
    create_script('echo "${BUNDLE_GEMFILE:-unset} $MSYNC_KEEP" > output')
    stub_const('ENV', ENV.to_h.merge('BUNDLE_GEMFILE' => '/configs/Gemfile', 'MSYNC_KEEP' => 'yes'))
    allow(git).to receive(:add).with(all: true)

    stage_changes

    expect(File.read(File.join(directory, 'output'))).to eq "unset yes\n"
  end

  it 'fails without staging anything when the pre-commit script fails' do
    create_script('exit 1')
    expect(git).not_to receive(:add)

    expect { stage_changes }.to raise_error(ModuleSync::Error, /Pre-commit script 'autofix' failed/)
  end

  it 'fails when the pre-commit script does not exist' do
    expect { stage_changes('missing') }.to raise_error(ModuleSync::Error, "Pre-commit script 'missing' not found")
  end
end
