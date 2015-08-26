#!py

import pprint
import os
import time
import json
import requests
import binascii
import M2Crypto
import salt.utils.smtp as smtp
import salt.config as config


def run():
    '''
    Run the reactor
    '''
    sns = data['post']

    if 'SubscribeURL' in sns:
        # This is just a subscription notification
        msg_kwargs = {
            'smtp.subject': 'EC2 Autoscale Subscription (via Salt Reactor)',
            'smtp.content': '{0}\r\n'.format(pprint.pformat(sns)),
        }
        smtp.send(msg_kwargs, __opts__)
        return {}

    url_check = sns['SigningCertURL'].replace('https://', '')
    url_comps = url_check.split('/')
    if not url_comps[0].endswith('.amazonaws.com'):
        # The expected URL does not seem to come from Amazon, do not try to
        # process it
        msg_kwargs = {
            'smtp.subject': 'EC2 Autoscale SigningCertURL Error (via Salt Reactor)',
            'smtp.content': (
                'There was an error with the EC2 SigningCertURL. '
                '\r\n{1} \r\n{2} \r\n'
                'Content received was:\r\n\r\n{0}\r\n').format(
                    pprint.pformat(sns), url_check, url_comps[0]
                ),
        }
        smtp.send(msg_kwargs, __opts__)
        return {}

    if not 'Subject' in sns:
        sns['Subject'] = ''

    pem_request = requests.request('GET', sns['SigningCertURL'])
    pem = pem_request.text

    str_to_sign = (
        'Message\n{Message}\n'
        'MessageId\n{MessageId}\n'
        'Subject\n{Subject}\n'
        'Timestamp\n{Timestamp}\n'
        'TopicArn\n{TopicArn}\n'
        'Type\n{Type}\n'
    ).format(**sns)

    cert = M2Crypto.X509.load_cert_string(str(pem))
    pubkey = cert.get_pubkey()
    pubkey.reset_context(md='sha1')
    pubkey.verify_init()
    pubkey.verify_update(str_to_sign.encode())

    decoded = binascii.a2b_base64(sns['Signature'])
    result = pubkey.verify_final(decoded)

    if result != 1:
        msg_kwargs = {
            'smtp.subject': 'EC2 Autoscale Signature Error (via Salt Reactor)',
            'smtp.content': (
                'There was an error with the EC2 Signature. '
                'Content received was:\r\n\r\n{0}\r\n').format(
                    pprint.pformat(sns)
                ),
        }
        smtp.send(msg_kwargs, __opts__)
        return {}

    message = json.loads(sns['Message'])
    instance_id = str(message['EC2InstanceId'])

    if 'launch' in sns['Subject']:
        vm_ = __opts__.get('ec2.autoscale', {})
        vm_['reactor'] = True
        vm_['instances'] = instance_id
        vm_['instance_id'] = instance_id
        vm_list = []
        for key, value in vm_.iteritems():
            if not key.startswith('__'):
                vm_list.append({key: value})
        # Fire off an event to wait for the machine
        ret = {
            'ec2_autoscale_launch': {
                'runner.cloud.create': vm_list
            }
        }
    elif 'termination' in sns['Subject']:
        ret = {
            'ec2_autoscale_termination': {
                'wheel.key.delete': [
                    {'match': instance_id},
                ]
            }
        }

    return ret
