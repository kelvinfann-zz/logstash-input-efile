# Logstash Plugin Input - Enhanced File (efile)

This is an input plugin for [Logstash](https://github.com/elasticsearch/logstash).

It is more or less follows the built-in logstash file input except it differs in a couple key ways:
  1. Offsets are stored by the plugin itself, and then 
  2. Messages get enhanced to include their origin, offsets, and message length.


## Disclaimer

Again, this plugin more or less follows the logstash [file-input plugin code](https://github.com/logstash-plugins/logstash-input-file). The majority of the code is just juryrigged to work, so you should see a good amount of identical code.

## Documentation

Since this code is just juryrigged from the logstash file plugin, the [logstash official documentation](https://www.elastic.co/guide/en/logstash/current/plugins-inputs-file.html) covers most of the config possibilities 
