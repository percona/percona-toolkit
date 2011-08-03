.. highlight:: perl


***********
ENVIRONMENT
***********


The environment variable \ ``PTDEBUG``\  enables verbose debugging output to STDERR.
To enable debugging and capture all output to a file, run the tool like:


.. code-block:: perl

    PTDEBUG=1 pt-table-checksum ... > FILE 2>&1


Be careful: debugging output is voluminous and can generate several megabytes
of output.

