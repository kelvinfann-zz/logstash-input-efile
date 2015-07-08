# Logstash Plugin Input - Enhanced File (efile)

This is an input plugin for [Logstash](https://github.com/elasticsearch/logstash).

It is more or less follows the built-in logstash file input except it differs in a couple key ways:
  1. Offsets are stored by the plugin itself, and then 
  2. Messages get enhanced to include their origin, offsets, and message length.


## Disclaimer

Again, this plugin more or less follows the logstash [file-input plugin code](https://github.com/logstash-plugins/logstash-input-file). The majority of the code is just juryrigged to work, so you should see a good amount of identical code.

Also, please note that by using this plugin by itself, without an enhanced filter or output, that this plugin occasionally be off by 1; that is to say that this input plugin may send at most a repeated message per time this plugin is turned off and turned back on.

## Documentation

Since this code is just juryrigged from the logstash file plugin, the [logstash official documentation](https://www.elastic.co/guide/en/logstash/current/plugins-inputs-file.html) covers most of the config possibilities 

The key differences you should see in the config file are:
  1. `offset_path` - where the offsets will be stored after shutdown/where the plugin will look for offsets initially. This requires an *absolute* path to a *file*. If undeclared the plugin will assume that it does not have any offsets
  2. `using_eoutput` - a boolean indicating if the output of the logstash job is part of the enhanced eseries of plugins. When this is turned on the input plugin

Also note that since this plugin handles offsets by itself, the config `sincedb_write_interval` becomes mostly useless. 
