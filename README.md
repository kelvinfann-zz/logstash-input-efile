# Logstash Plugin Input - Enhanced File (efile)

This is an input plugin for [Logstash](https://github.com/elasticsearch/logstash).

It is more or less follows the built-in log stash file input except it differs in a couple key ways.
1. Offsets are stored by the plugin itself, and then 
2. Messages get enhanced to include their origin, offsets, and message length.

##

## Documentation
