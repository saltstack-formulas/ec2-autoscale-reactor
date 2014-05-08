ec2-autoscale-reactor
=====================

This is a reactor formula, which allows the autoscaling feature in EC2 to
notify Salt when an instance is created, so that it may be automatically
bootstrapped and accepted by the Salt Master, or when an instance is deleted,
so that its key can be automatically removed from the Salt Master.


Dependencies
------------
The following packages must be installed:

.. code-block:: yaml

    - Salt (develop branch)
    - Salt API >= 0.8.4.1


Master Configuration
--------------------
The following files need to be configured on the Salt Master:

.. code-block:: yaml

    - /etc/salt/master
    - /etc/salt/cloud.providers.d/ec2.conf
    - /srv/reactor/ec2-autoscale.sls (from this package)

/etc/salt/master
~~~~~~~~~~~~~~~~
This reactor makes use of the web hooks system introduced in Salt API 0.8.4.
The configuration for Salt API is stored in the master configuration file:

.. code-block:: yaml

    external_auth:
      pam:
        myuser:
          - .*
          - '@runner'
          - '@wheel'
    
    rest_cherrypy:
      port: 8080
      host: 0.0.0.0
      webhook_url: /hook
      webhook_disable_auth: True

When a web request is received, Salt API will fire an event for the reactor
system to pick up:

.. code-block:: yaml

    reactor:
      - 'salt/netapi/hook/ec2/autoscale':
        - '/srv/reactor/ec2-autoscale.sls'

This reactor will examine the web hook received from EC2 and check its
authenticity. If issues are encountered, such as an invalid signature, or the
certificates being located outside of Amazon, a notification will be sent to
the user via email. The following settings are an example of SMTP settings that
might be used to connect to the mail server:

.. code-block:: yaml

    smtp.from: 'salt-master@example.com'
    smtp.to: admin1@example.com.com; admin2@example.com.com
    smtp.host: smtp.gmail.com
    smtp.username: 'salt-master@example.com'
    smtp.password: 'verybadpass'
    smtp.tls: True
    smtp.subject: 'Salt'

.. code-block:: yaml

Finally, some extra settings must be set up to point the reactor to the
necessary Salt Cloud provider setting. Any additional settings to be used on
the target minion, that are not configured in the provider configuration, can
also be set here.

.. code-block:: yaml

    ec2.autoscale:
      provider: my-ec2-config
      ssh_username: ec2-user

/etc/salt/cloud.providers.d/ec2.conf
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Existing Salt Cloud provider configuration can be used with this reactor.
Profile configuration is not necessary on the master; minions will be
configured as per the EC2 Autoscaling Group.

.. code-block:: yaml

    my-ec2-config:
      id: <aws id>
      key: <aws key>
      keyname: <my key name>
      securitygroup: <my security group>
      private_key: </path/to/my/priv_key.pem>
      location: us-east-1
      provider: ec2
      minion:
        master: saltmaster.example.com


/srv/reactor/ec2-autoscale.sls
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
This package includes a file in its ``reactor/`` directory called
``ec2-autoscale.sls``. Create the ``/src/reactor/`` directory on the Salt
Master if it doesn't already exist, and copy this file into it.


EC2 Configuration
-----------------
The following must be configured in the EC2 account to be used:

.. code-block:: yaml

    - SNS HTTP Notification
    - Launch Configuration
    - Autoscaling Group


SNS HTTP(S) Notification
~~~~~~~~~~~~~~~~~~~~~~~~
In order to notify the reactor that an instance is being autoscaled up or down,
AWS SNS must be configured with the URL to send the notification webhook to.
Both HTTP and HTTPS are available, but it is highly recommended that HTTPS is
used.

From the AWS Console, select SNS (Push Notification Service). This will take
you to the SNS dashboard.

Click the button to Create New Topic. Enter a Topic Name, and a human-readable
Display Name, and select the Create Topic button. This will take you to the
Topic Details area.

Inside the Topic Details, click the button to Create Subscription. Select HTTP
or HTTPS as appropriate, and enter the URL to your Salt API server as the
endpoint. Assuming it is set up at ``https://saltmaster.example.com/``, the
endpoint will look like:

.. code-block:: yaml

    https://saltmaster.example.com/hook/ec2/autoscale

In this URL, ``/hook`` notifies Salt API that a webhook is being used, and
``/ec2/autoscale`` will be used to tag the event that the reactor uses to
process it. The tag that will be created by this URL will be

.. code-block:: yaml

    salt/netapi/hook/ec2/autoscale

Clicking the Subscribe button will cause a subscription notification to be sent
immediately to the endpoint. If the Master configuration is correct, the
reactor will forward the subscription notication to the configured email
address(es). This message will contain a subscribe URL which, when visited,
will activate the Subscription.

If the Salt Master is not properly configured, the endpoint can be re-entered,
and another subscription notifcation will be sent. It should be noted that once
configured, a subscription may not be deleted via the web interface until the
subscribe URL has been visited and confirmed.


Launch Configuration
~~~~~~~~~~~~~~~~~~~~
In order to start autoscaling instances, EC2 requires a launch configuration to
be set. This defines the EC2-specific variables (AMI, disks, etc.) that will be
used to spin up new instances.

From the AWS Console, select EC2 (Virtual Servers in the Cloud), which will
lead to the EC2 Management Console. From there, select Launch Configurations
from the left-hand menu.

Click the Create Launch Configuration button. Follow the wizard to select the
appropriate AMI and configuration to use. At the Review screen, click the
Create Launch Configuration button to save.


Autoscaling Group
~~~~~~~~~~~~~~~~~
Once a launch configuration is defined, an autoscaling group may be configured
which defines variables such as the minimum and maximum number of instances,
and under what circumstances to add and remove instances.

From the AWS Console, select Auto Scaling Groups from the left-hand menu. Click
the Create Auto Scaling Group button. Select the option to "Create an Auto
Scaling group from an existing launch configuration". Select the Launch
Configuration, and click Next Step.

Follow the wizard to the "Configure Notifications" screen. Click the "Add
Notification" button and select the notification that was configured on SNS.
Complete the wizard as normal.


Basic Usage
-----------
Once the Salt Master and AWS have been configured, the reactor will manage
itself. When the autoscaler adds a new instance, Salt Cloud will be notified to
wait for it to become available, and bootstrap it with Salt. Its key will be
automatically accepted, and if the minion configuration includes the appropriate
startup state, then the minion will configure itself, and go to work.

When the autoscaler spins down a machine, the Wheel system inside of Salt will
be notified to delete its key from the master. This causes instances to be
completely autonomous, both in setup and tear-down.

Caveats
-------
As instances will be launched and destroyed automatically by EC2, they will not
have the opportunity to be configured with user-definable names, and will
therefore be identified to the master by their ``instance-id``. In the event
that more detailed identifying information needs to be available, the instances
should be configured to include EC2 tags, which can later be read and displayed
to the user via Salt Cloud.

