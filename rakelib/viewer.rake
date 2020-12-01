namespace :viewer do
  # Provision the `viewer` node from the `provision.yaml` and install the dashboard
  # Note that this will bind to ports 3000 and 8086 on the local machine
  # Ensure that there are not other litmus machines present when running this task
  desc 'Provisions a local metrics dashboard instance'
  task :provision do
    require 'puppet_litmus'
    require 'bolt_spec/run'

    puts 'Provisioning the node'
    Rake::Task['litmus:provision_install'].invoke('viewer', 'puppet6')

    inventory_hash = PuppetLitmus::InventoryManipulation.inventory_hash_from_inventory_file
    targets = PuppetLitmus::InventoryManipulation.find_targets(inventory_hash, nil)
    machine_name = targets.first unless targets.nil?

    puts 'Preparing the node'
    result = BoltSpec::Run.run_command('puppet resource package toml-rb ensure=installed provider=puppet_gem', machine_name, inventory: inventory_hash.clone)
    raise "Failed to install toml-rb on the node: #{result}" unless result.first['status'] == 'success'

    puts 'Applying the dashboard class. This may take a while'
    manifest = 'class{"puppet_metrics_dashboard":
      add_dashboard_examples => true,
      overwrite_dashboards => false,
      configure_telegraf => false,
      enable_telegraf => false,
      influxdb_database_name => ["puppet_metrics"]
    }'
    config_data = { 'modulepath' => File.join(Dir.pwd, 'spec', 'fixtures', 'modules') }
    BoltSpec::Run.apply_manifest(manifest, machine_name, execute: true, config: config_data, inventory: inventory_hash.clone)
    result = BoltSpec::Run.apply_manifest(manifest, machine_name, execute: true, config: config_data, inventory: inventory_hash.clone)
    raise "Failed to install the dashboard : #{result}" unless result.first['status'] == 'success'

    puts 'The dashboard is available on http://localhost:3000 and data can be imported in http://localhost:8086'
    puts 'The default login is admin:admin'
  end

  # Import metrics into the provisioned dashboard
  # Takes a parameter of the file location on disk of the metrics directory
  # Taks a second parameter of the number of days to load. Defaults to 30.
  desc 'Imports metrics data into a local metrics dashboard instance'
  task :import, [:metrics_location, :days] do |_t, args|
    require 'open3'
    raise 'Cannot find metrics directory' unless File.directory?(args[:metrics_location])

    # Ensure that the puppet_metrics_collector module has been installed into fixtures.
    Rake::Task['spec_prep'].invoke

    script_args = "--pattern \"#{args[:metrics_location]}/**/*.json\" --netcat 127.0.0.1 --convert-to influxdb --influx-db puppet_metrics"
    script_path = File.join(Dir.pwd, 'spec', 'fixtures', 'modules', 'puppet_metrics_collector', 'files', 'json2timeseriesdb')
    raise 'Cannot find json2timeseriesdb' unless File.file?(script_path)

    puts 'Importing metrics. This will take a while, but metrics will populate the in the dashboard during this time. Only STDERR will be displayed'
    Open3.popen3("ruby #{script_path} #{script_args}") do |stdout, stderr, status, thread|
      puts stderr.read
    end
  end

  desc 'Destroys metrics dashboard instance'
  task :destroy do
    puts 'Destroying the node'
    Rake::Task['litmus:tear_down'].invoke
  end
end

task :viewer, [:metrics_location, :days] do |_t, args|
  Rake::Task['viewer:provision'].invoke
  Rake::Task['viewer:import'].invoke(args[:metrics_location], args[:days])
end
