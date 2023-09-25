.. _pt-galera-log-explainer:

==================================
:program:`pt-galera-log-explainer`
==================================

Filter, aggregate and summarize multiple galera logs together.
This is a toolbox to help navigating Galera logs.

Usage
=====

.. code-block:: bash
    pt-galera-log-explainer [--since=] [--until=] [-vvv] [--merge-by-directory] [--pxc-operator] <command> <paths ...>

Commands available
==================

list
~~~~

.. code-block:: bash
    pt-galera-log-explainer [flags] list { --all | [--states] [--views] [--events] [--sst] [--applicative] } <paths ...>

List key events in chronological order from any number of nodes (sst, view changes, general errors, maintenance operations)
It will aggregates logs together by identifying them using node names, IPs and internal Galera identifiers. 



It can be from a single node
.. code-block:: bash
    pt-galera-log-explainer list --all --since 2023-01-05T03:24:26.000000Z /var/log/mysql/``*``.log

or from multiple nodes
.. code-block:: bash
    pt-galera-log-explainer list --all ``*``.log

You can filter by type of events
.. code-block:: bash
    pt-galera-log-explainer list --sst --views ``*``.log


whois
~~~~~
Find out information about nodes, using any type of info
.. code-block:: bash
    pt-galera-log-explainer whois '218469b2' mysql.log 
    {
    	"input": "218469b2",
    	"IPs": [
    		"172.17.0.3"
    	],
    	"nodeNames": [
    		"galera-node2"
    	],
    	"hostname": "",
    	"nodeUUIDs:": [
    		"218469b2",
    		"259b78a0",
    		"fa81213d",
    	]
    }

Using any type of information
.. code-block:: bash
    pt-galera-log-explainer whois '172.17.0.3' mysql.log 
    pt-galera-log-explainer whois 'galera-node2' mysql.log 


conflicts
~~~~~~~~~

List every replication failure votes (Galera 4)
.. code-block:: bash
    pt-galera-log-explainer conflicts [--json|--yaml] ``*``.log

ctx
~~~

Get the tool crafted context for a single log.
It will contain everything the tool extracted from the log file: version, sst information, known uuid-ip-nodename mappings, ...
.. code-block:: bash
    pt-galera-log-explainer ctx mysql.log

regex-list
~~~~~~~~~~

Will print every implemented regexes:
* regex: the regex that will be used against the log files
* internalRegex: the golang regex that will be used to extract piece of information
* type: the regex group it belong to
* verbosity: the required level of verbosity to which it will be printed

.. code-block:: bash
    pt-galera-log-explainer regex-list

Available flags
~~~~~~~~~~~~~~~

``-h``, ``--help``               
    Show help and exit.

``--no-color``
    Remove every color special characters 

``--since``        
    Only list events after this date. It will affect the regex applied to the logs.
    Format: 2023-01-23T03:53:40Z (RFC3339)

``--until``
    Only list events before this date. This is only implemented in the tool loop, it does not alter regexes.
    Format: 2023-01-23T03:53:40Z (RFC3339)

``--merge-by-directory``
    Instead of relying on extracted information, logs will be merged by their base directory 
    It is useful when logs are very sparsed and already organized by nodes.

``-v``, ``--verbosity``        
    ``-v``: Detailed  
    ``-vv``: DebugMySQL, add every mysql info the tool used
    ``-vvv``: internal tool debug
    Default: ``-v``

``--pxc-operator``       
    Analyze logs from Percona PXC operator. 
    It will prevent logs from being merged together, add operator specific regexes, and fine-tune regexes for logs taken from pt-k8s-debug-collector
    Off by default because it negatively impacts performance for non-k8s setups.

``--exclude-regexes``
    Remove regexes from analysis. Use 'pt-galera-log-explainer regex-list' to have the list
    
``--grep-cmd``
    grep v3 binary command path. For Darwin systems, it could need to be set to 'ggrep'
    Default: ``grep``

``--grep-args``     
    grep arguments. perl regexp (-P) is necessary. -o will break the tool
    Default: ``-P``



Compatibility
=============

* Percona XtraDB Cluster: 5.5 to 8.0
* MariaDB Galera Cluster: 10.0 to 10.6
* logs from PXC operator pods (error.log, recovery.log, post.processing.log)

Known issues
============

* Sparse files identification can be missed, resulting in many columns displayed. ``--merge-by-directory`` can be used, but files need to be organized already in separate directories
  This is mainly when the log file does not contain enough information.
* Some information will seems missed. Depending on the case, it may be simply unimplemented yet, or it was disabled later because it was found to be unreliable (node index numbers are not reliable for example)
* Columns width are sometimes too large to be easily readable. This usually happens when printing SST events with long node names
