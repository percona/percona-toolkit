.. _install:

==========================
Installing Percona Toolkit
==========================

Percona provides packages for most popular 64-bit Linux distributions:

* Debian 7 ("wheezy")
* Debian 8 ("jessie")
* Ubuntu 14.04 LTS (Trusty Tahr)
* Ubuntu 16.04 LTS (Xenial Xerus)
* Ubuntu 16.10 (Yakkety Yak)
* Ubuntu 17.04 (Zesty Zapus)
* Red Hat Enterprise Linux or CentOS 6 (Santiago)
* Red Hat Enterprise Linux or CentOS 7 (Maipo)

.. note:: Percona Toolkit should work on other DEB-based and RPM-based systems
   (for example, Oracle Linux and Amazon Linux AMI),
   but it is tested only on those listed above.

It is recommended to install Percona software from official repositories:

1. Configure Percona repositories as described in
   `Percona Software Repositories Documentation
   <https://www.percona.com/doc/percona-repo-config/index.html>`_.

#. Install Percona Toolkit using the corresponding package manager:

   * For Debian or Ubuntu::

      sudo apt-get install percona-toolkit

   * For RHEL or CentOS::

      sudo yum install percona-toolkit

.. rubric:: Generating an instance UUID for statistics
	    
During the installating process, the percona-toolkit installer records a unique
identifier specific to the given percona-toolkit instance. This ID is a the
product UUID stored in |product-uud|. The installer copies the product_uuid to
|toolkit-uuid|.

This unique identifier is used when collecting statistics about the usage of
percona-toolkit. Note that no other information is gathered for this purpose.

In cases when the installer is not able to read the contents of
|product-uuid|, a random UUID is generated. A random UUID is
also generated if percona-toolkit is run from the binary in the *tar.gz* file.
      
Alternative Install Methods
===========================

You can also download the packages from the
`Percona web site <https://www.percona.com/downloads/percona-toolkit/>`_
and install it using tools like ``dpkg`` and ``rpm``,
depending on your system.
For example, to download the package for Debian 8 ("jessie"),
run the following::

 wget https://www.percona.com/downloads/percona-toolkit/3.0.3/binary/debian/jessie/x86_64/percona-toolkit_3.0.3-1.jessie_amd64.deb

If you want to download a specific tool, use the following address:
http://www.percona.com/get

For example, to download the ``pt-summary`` tool, run::

 wget percona.com/get/pt-summary


.. |toolkit-uuid| replace:: :file:`/etc/percona-toolkit/.percona.toolkit.uuid`
.. |product-uuid| replace:: :file:`/sys/class/dmi/id/product_uuid`
