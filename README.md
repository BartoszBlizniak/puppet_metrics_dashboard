# puppet_metrics_dashboard

- [Description](#Description)
- [Setup](#Setup)
  - [Upgrade notes](#Upgrade-notes)
  - [Determining where Telegraf runs](#Determining-where-Telegraf-runs)
  - [Requirements](#Requirements)
- [Usage](#Usage)
  - [Configure a Monolithic Master and a Dashboard node](#Configure-a-Monolithic-Master-and-a-Dashboard-node)
  - [Manual configuration of a complex Puppet Infrastructure](#Manual-configuration-of-a-complex-Puppet-Infrastructure)
  - [Configure Graphite](#Configure-Graphite)
  - [Configure Telegraf, Graphite, and Archive](#Configure-Telegraf,-Graphite,-and-Archive)
  - [Allow Telegraf to access PE-PostgreSQL](#Allow-Telegraf-to-access-PE-PostgreSQL)
  - [Enable SSL](#Enable-SSL)
  - [Profile defined types](#Profile-defined-types)
  - [Other possibilities](#Other-possibilities)
- [Reference](#Reference)
- [Limitations](#Limitations)
  - [Repository failure for InfluxDB packages](#Repository-failure-for-InfluxDB-packages)
  - [PostgreSQL metrics collection with older versions of Telegraf](#PostgreSQL-metrics-collection-with-older versions-of-Telegraf)
- [Development](#Development)

## Description

This module is used to configure Telegraf, InfluxDB, and Grafana, and collect, store, and display metrics collected from Puppet services.
By default, those components are installed on a separate Dashboard node by applying the base class of this module to that node.
That class will automatically query PuppetDB for Puppet Infrastructure nodes (Masters, PuppetDB hosts, PostgreSQL hosts) or you can specify them via associated class parameters.
It is not recommended to apply the base class of this module to one of your Puppet Infrastructure nodes.

You have the option to use the [included defined types](#profile-defined-types) to configure Telegraf to run on each Puppet Infrastructure node,
with the metrics being stored and displayed by another node running InfluxDB and Grafana.  
In environments where there is an existing InfluxDB/Grafana installation, this option is recommended.
See [Determining where Telegraf runs](#determining-where-telegraf-runs) for details.

You have the option of collecting metrics using any or all of the following methods:

- Via Telegraf, which polls Puppet service endpoints (default, recommended)
- Via Puppet Server's [built-in Graphite support](https://puppet.com/docs/pe/latest/getting_started_with_graphite.html) (Section: Enabling Puppet Server's Graphite support)
- Via Archive files imported from the [puppetlabs/puppet_metrics_collector](https://forge.puppet.com/puppetlabs/puppet_metrics_collector) module

## Setup

### Upgrade notes

* Version 2 and up now requires the `toml-rb` gem installed on the Master and any/all Compilers.
* The `puppet_metrics_dashboard::profile::postgres` class is deprecated in favor of the `puppet_metrics_dashboard::profile::master::postgres_access` class.
* Parameters `telegraf_agent_interval` and `http_response_timeout` were previously Integers but are now Strings. The value should match a time interval, such as `5s`, `10m`, or `1h`.
* `influxdb_urls` was previously a String, but is now an Array.

Previous versions of this module added several `[[inputs.httpjson]]` entries in `/etc/telegraf/telegraf.conf`.
These entries should be removed, as all module-specific settings now reside in individual files within `/etc/telegraf/telegraf.d/`.
Telegraf will continue to work if you do not remove them, however, the old `[[inputs.httpjson]]` will not be updated going forward.

### Determining where Telegraf runs

Telegraf can be configured to run on the Dashboard node, or on each Puppet Infrastructure node.
By default, this module configures Telegraf on the Dashboard node by querying PuppetDB to identify each Puppet Infrastructure node.
To manually configure Telegraf on the Dashboard node, define the following `puppet_metrics_dashboard` class parameters: `master_list`, `puppetdb_list` and `postgres_host_list`.

To configure Telegraf to run on each Puppet Infrastructure node, use the corresponding profiles for those nodes.
See [Profile defined types](#profile-defined-types).
Apply the `puppet_metrics_dashboard` class to the Dashboard node to configure InfluxDB and Grafana, and apply the profile classes on each Puppet Infrastructure node to configure Telegraf.

### Requirements

The [toml-rb](https://github.com/emancu/toml-rb) gem is a requirement of the `puppet-telegraf` module, and needs to be installed in Puppet Server on the Master and any/all Compilers.

Apply the following class to the Master and any/all Compilers to install the gem.

```puppet
node 'master.example.com' {
  include puppet_metrics_dashboard::profile::master::install
}
node 'compiler.example.com' {
  include puppet_metrics_dashboard::profile::master::install
}
```

Or, you can apply the `puppet_metrics_dashboard::profile::master::install` class to the `PE Master` Node Group, if using Puppet Enterprise. 

Or, you can manually install the gem using the following command.

```bash
puppetserver gem install toml-rb
```

Restart the Puppet Server service after manually installing the gem.

If you are configuring the Dashboard node via a `puppet apply` workflow, you will need to install the gem into Puppet on that host.

## Usage

### Configure a Monolithic Master and a Dashboard node

```puppet
node 'master.example.com' {
  include puppet_metrics_dashboard::profile::master::install
  include puppet_metrics_dashboard::profile::master::postgres_access
}

node 'dashboard.example.com' {
  class { 'puppet_metrics_dashboard':
    add_dashboard_examples => true,
    overwrite_dashboards   => false,
  }
}
```

This will configure Telegraf, InfluxDB, and Grafana on the Dashboard node, and allow Telegraf on that host to access PostgreSQL on the Monolithic Master.

Note that the `add_dashboard_examples` parameter enforces state on the example dashboards.
Setting the `overwrite_dashboards` parameter to `true` disables overwriting your modifications (if any) to the example dashboards.

### Manual configuration of a complex Puppet Infrastructure

```puppet
node 'master.example.com' {
  include puppet_metrics_dashboard::profile::master::install
}
node 'compiler01.example.com' {
  include puppet_metrics_dashboard::profile::master::install
}
node 'compiler02.example.com' {
  include puppet_metrics_dashboard::profile::master::install
}
node 'postgres01.example.com' {
  include puppet_metrics_dashboard::profile::master::postgres_access
}
node 'postgres02.example.com' {
  include puppet_metrics_dashboard::profile::master::postgres_access
}

node 'dashboard.example.com' {
  class { 'puppet_metrics_dashboard':
    add_dashboard_examples => true,
    overwrite_dashboards   => false,
    master_list            => ['master.example.com', ['compiler01.example.com', 9140], ['compiler02.example.com', 9140]],
    puppetdb_list          => ['puppetdb01.example.com', 'puppetdb02.example.com'],
    postgres_host_list     => ['postgres01.example.com', 'postgres02.example.com'],
  }
}
# Alternate ports are configured using a pair of: [host_name, port_number]
```

Note that the defaults for this module's class parameters are defined in its `data/common.yaml` directory.

The `*_list` parameters can be defined in the class declaration, or elsewhere in Hiera. For example:

```
puppet_metrics_dashboard::master_list:
  - "master.example.com"
  - ["compiler01.example.com", 9140]
  - ["compiler02.example.com", 9140]
puppet_metrics_dashboard::puppetdb_list:
  - "puppetdb01.example.com"
  - "puppetdb02.example.com"
puppet_metrics_dashboard::postgres_host_list:
  - "postgres01.example.com"
  - "postgres02.example.com"
```

### Configure Graphite

```puppet
node 'dashboard.example.com' {
  class { 'puppet_metrics_dashboard':
    add_dashboard_examples => true,
    overwrite_dashboards   => false,
    consume_graphite       => true,
    influxdb_database_name => ['graphite'],
    master_list            => ['master', 'master02'],
  }
}
```

* This method requires enabling Graphite on the Masters, as described [here](https://puppet.com/docs/pe/latest/puppet_server_metrics/getting_started_with_graphite.html#enabling-puppet-server-graphite-support).
The hostnames that you use in `master_list` must match the value(s) that you used for `metrics_server_id` in the `puppet_enterprise::profile::master` class.
You must use hostnames rather than fully-qualified domain names (no dots) both in this class and in the  `puppet_enterprise::profile::master` class.

### Configure Telegraf, Graphite, and Archive

Archive refers to files imported from the [puppetlabs/puppet_metrics_collector](https://forge.puppet.com/puppetlabs/puppet_metrics_collector) module.

```puppet
node 'dashboard.example.com' {
  class { 'puppet_metrics_dashboard':
    add_dashboard_examples => true,
    overwrite_dashboards   => false,
    consume_graphite       => true,
    influxdb_database_name => ['telegraf', 'graphite', 'puppet_metrics'],
  }
}
```

### Allow Telegraf to access PE-PostgreSQL

The following class is required to be applied to the Master (or the PE Database node if using external PostgreSQL) for collection of PostgreSQL metrics via Telegraf.

```puppet
node 'master.example.com' {
  class { 'puppet_metrics_dashboard::profile::master::postgres_access':
    telegraf_host => 'grafana-server.example.com',
  }
}
```

The `telegraf_host` parameter is optional. 
By default, the class will query PuppetDB for Dashboard nodes (with the `puppet_metrics_dashboard` class applied) and use the `certname` of the first node in the results.
If the PuppetDB lookup fails to find a Dashboard node, and you do not specify `telegraf_host` then the class outputs a warning.

Refer to [Issue 72](https://github.com/puppetlabs/puppet_metrics_dashboard/issues/72) if the above generates the following error:

```
Error: Could not retrieve catalog from remote server: Error 500 on SERVER: Server Error: Evaluation Error: Error while evaluating a Resource Statement, Evaluation Error: Error while evaluating a Function Call, 'versioncmp' parameter 'a' expects a String value, got Undef (file: /opt/puppetlabs/puppet/modules/pe_postgresql/manifests/server/role.pp, line: 66, column: 6) (file: /etc/puppetlabs/code/environments/production/modules/puppet_metrics_dashboard/manifests/profile/master/postgres_access.pp, line: 42) on node master.example.com
```

A workaround for that error is to apply the `puppet_metrics_dashboard::profile::master::postgres_access` class to the `PE Database` Node Group in the Console, if using Puppet Enterprise. 

### Enable SSL

```puppet
node 'dashboard.example.com' {
  class { 'puppet_metrics_dashboard':
    use_dashboard_ssl => true,
  }
}
```

By default, this will create a set of certificates in `/etc/grafana` that are based on the Dashboard node's Puppet agent certificates.
You can also specify different files by defining the `dashboard_cert_file` and `dashboard_cert_key` parameters, but managing certificate content or supplying your own certificates is unsupported by this module.

Note that enabling SSL on Grafana will not allow for running on privileged ports such as `443`.
To enable that capability, use the suggestions documented in [the Grafana documentation](http://docs.grafana.org/installation/configuration/#http-port)

### Profile defined types

The module includes defined types that you can use with an existing Grafana implementation.
See [REFERENCE.md](REFERENCE.md) for example usage.

Note that because of the way that the Telegraf module works, these examples will overwrite any configuration in `telegraf.conf` if it is *not* already managed by Puppet.
See the [puppet-telegraf documentation](https://forge.puppet.com/puppet/telegraf#usage) on how to manage that file and add other settings.

### Other possibilities

Configure the password for InfluxDB , enable additional [TICK Stack](https://www.influxdata.com/time-series-platform/) components, and customize Grafana.

```puppet
node 'dashboard.example.com' {
  class { 'puppet_metrics_dashboard':
    influx_db_password  => 'secret',
    enable_chronograf   => true,
    enable_kapacitor    => true,
    grafana_http_port   => 3333,
    grafana_version     => '6.5.2',
  }
}
```

## Reference

This module is documented via `pdk bundle exec puppet strings generate --format markdown`.
Please refer to [REFERENCE.md](REFERENCE.md) for more information.

## Limitations

### Repository failure for InfluxDB packages

When installing InfluxDB on CentOS/RedHat 6/7 you may encounter the following error message.

```puppet
Error: Execution of '/usr/bin/yum -d 0 -e 0 -y install telegraf' returned 1: Error: Cannot retrieve repository metadata (repomd.xml) for repository: influxdb. Please verify its path and try again
Error: /Stage[main]/Puppet_metrics_dashboard::Telegraf/Package[telegraf]/ensure: change from purged to present failed: Execution of '/usr/bin/yum -d 0 -e 0 -y install telegraf' returned 1: Error: Cannot retrieve repository metadata (repomd.xml) for repository: influxdb. Please verify its path and try again
```

This is due to a mismatch in the ciphers available in the operating system and on the InfluxDB repository.
To resolve this issue, update `nss` and `curl` on the Dashboard node.

```bash
yum install curl nss --disablerepo influxdb
```

### PostgreSQL metrics collection with older versions of Telegraf

PostgreSQL metrics collection requires Telegraf version 1.9.1 or later.

## Development

Please refer to [CONTRIBUTING.md](CONTRIBUTING.md) for more information.
