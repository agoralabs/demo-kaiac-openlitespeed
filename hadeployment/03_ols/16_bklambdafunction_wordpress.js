const AWS = require('aws-sdk');

// Configuration robuste du SDK AWS
AWS.config.update({
  region: process.env.AWS_REGION_APP || 'us-west-2',
  maxRetries: 3,
  retryDelayOptions: { base: 300 },
  httpOptions: {
    connectTimeout: 5000,
    timeout: 10000
  }
});

// Clients AWS avec configuration explicite
const clients = {
  route53: new AWS.Route53(),
  elbv2: new AWS.ELBv2(),
  ec2: new AWS.EC2(),
  sqs: new AWS.SQS(),
  ssm: new AWS.SSM()
};

// Fonction améliorée pour trouver un ALB par tag
async function findAlbByTag(tagName, tagValue) {
  try {
    console.log(`Recherche ALB avec tag ${tagName}=${tagValue}`);
    
    const { LoadBalancers } = await clients.elbv2.describeLoadBalancers().promise();
    if (!LoadBalancers || LoadBalancers.length === 0) {
      throw new Error('Aucun ALB trouvé dans la région');
    }

    for (const alb of LoadBalancers) {
      try {
        if (!alb.LoadBalancerArn?.startsWith('arn:aws:elasticloadbalancing')) {
          continue;
        }

        const { TagDescriptions } = await clients.elbv2.describeTags({
          ResourceArns: [alb.LoadBalancerArn]
        }).promise();

        const hasMatchingTag = TagDescriptions[0].Tags.some(
          tag => tag.Key === tagName && tag.Value === tagValue
        );

        if (hasMatchingTag) {
          console.log('ALB trouvé:', {
            dnsName: alb.DNSName,
            hostedZoneId: alb.CanonicalHostedZoneId,
            arn: alb.LoadBalancerArn
          });
          return alb;
        }
      } catch (error) {
        console.error(`Erreur sur l'ALB ${alb.LoadBalancerArn}`, error.message);
      }
    }

    throw new Error(`ALB avec tag ${tagName}=${tagValue} non trouvé`);
  } catch (error) {
    console.error('Erreur dans findAlbByTag:', error);
    throw error;
  }
}

// Fonction pour gérer les enregistrements DNS
async function manageDNSRecord(action, record, domain, alb) {
  try {
    const hostedZones = await clients.route53.listHostedZonesByName({
      DNSName: domain
    }).promise();

    if (!hostedZones.HostedZones.length) {
      throw new Error(`Aucune zone hébergée pour ${domain}`);
    }

    const hostedZoneId = hostedZones.HostedZones[0].Id.replace('/hostedzone/', '');
    
    const params = {
      HostedZoneId: hostedZoneId,
      ChangeBatch: {
        Changes: [{
          Action: action,
          ResourceRecordSet: {
            Name: record,
            Type: 'A',
            AliasTarget: {
              HostedZoneId: alb.CanonicalHostedZoneId,
              DNSName: alb.DNSName,
              EvaluateTargetHealth: false
            }
          }
        }]
      }
    };

    console.log(`Envoi de la requête ${action} DNS pour ${domain}`);
    return await clients.route53.changeResourceRecordSets(params).promise();
  } catch (error) {
    console.error(`Erreur lors de l'opération DNS ${action}`, error);
    throw error;
  }
}

// Fonction principale pour créer un site WordPress
async function createWordPress(instanceId, message) {
  const command = [
    process.env.SCRIPT_COMMAND || '/home/ubuntu/deploy_wordpress.sh',
    `"${message.record}.${message.domain}"`,
    `"${message.domain_folder}"`,
    `"${message.wp_db_name}"`,
    `"${message.wp_db_user}"`,
    `"${message.wp_db_password}"`,
    `"${process.env.MYSQL_DB_HOST || 'localhost'}"`,
    `"${process.env.MYSQL_ROOT_USER || 'root'}"`,
    `"${process.env.MYSQL_ROOT_PASSWORD}"`,
    `"${message.php_version || 'lsphp81'}"`,
    `"${message.wp_version || 'latest'}"`
  ].join(' ');

  console.log('Exécution de la commande SSM:', command);
  
  await clients.ssm.sendCommand({
    InstanceIds: [instanceId],
    DocumentName: 'AWS-RunShellScript',
    Parameters: { commands: [command] },
    TimeoutSeconds: 300
  }).promise();

  const alb = await findAlbByTag(
    process.env.ALB_TAG_NAME || 'Name',
    process.env.ALB_TAG_VALUE
  );
  
  return await manageDNSRecord('UPSERT', message.record, message.domain, alb);
}

// Fonction pour supprimer un site WordPress
async function deleteWordPress(instanceId, message) {
  const command = [
    process.env.DELETE_SCRIPT_COMMAND || '/home/ubuntu/delete_wordpress.sh',
    `"${message.record}.${message.domain}"`,
    `"${message.domain_folder}"`,
    `"${message.wp_db_name}"`,
    `"${process.env.MYSQL_ROOT_USER || 'root'}"`,
    `"${process.env.MYSQL_ROOT_PASSWORD}"`
  ].join(' ');

  console.log('Exécution de la commande de suppression:', command);
  
  await clients.ssm.sendCommand({
    InstanceIds: [instanceId],
    DocumentName: 'AWS-RunShellScript',
    Parameters: { commands: [command] },
    TimeoutSeconds: 300
  }).promise();

  try {
    const alb = await findAlbByTag(
      process.env.ALB_TAG_NAME || 'Name',
      process.env.ALB_TAG_VALUE
    );
    await manageDNSRecord('DELETE', message.record, message.domain, alb);
  } catch (error) {
    console.error('Erreur lors de la suppression DNS (peut être normale si le record n\'existait pas):', error.message);
  }
}

exports.handler = async (event) => {
  console.log('Événement reçu:', JSON.stringify(event, null, 2));

  try {
    // Validation de base
    console.log(`Validation de base`);
    if (!event.Records || !Array.isArray(event.Records)) {
      throw new Error('Format d\'événement invalide');
    }

    for (const record of event.Records) {
      try {
        const message = JSON.parse(record.body);
        console.log('Traitement du message:', message);

        if (!['CREATE_WP', 'DELETE_WP'].includes(message.command)) {
          throw new Error(`Commande invalide: ${message.command}`);
        }
        console.log(`Trouver l'instance EC2`);
        // Trouver l'instance EC2
        const { Reservations } = await clients.ec2.describeInstances({
          Filters: [{
            Name: `tag:${process.env.EC2_TAG_NAME || 'Name'}`,
            Values: [process.env.EC2_TAG_VALUE]
          }]
        }).promise();

        const instanceId = Reservations?.[0]?.Instances?.[0]?.InstanceId;
        if (!instanceId) throw new Error('Instance EC2 non trouvée');

        console.log(`Instance EC2 non trouvée ${instanceId}`);

        console.log(`Exécuter la commande appropriée ${message.command}`);
        // Exécuter la commande appropriée
        if (message.command === 'CREATE_WP') {
          await createWordPress(instanceId, message);
          console.log(`Site WordPress créé pour ${message.record}.${message.domain}`);
          
        } else {
          await deleteWordPress(instanceId, message);
          console.log(`Site WordPress supprimé pour ${message.record}.${message.domain}`);
        }

        console.log(`Commande appropriée ${message.command} exécutée`);

        console.log(`Supprimer le message SQS ${record.eventSourceARN}`);
        // Supprimer le message SQS
        await clients.sqs.deleteMessage({
          QueueUrl: record.eventSourceARN,
          ReceiptHandle: record.receiptHandle
        }).promise();

        console.log(`Message supprimé de la queue SQS ${record.eventSourceARN}`);

      } catch (recordError) {
        console.error('Erreur de traitement du message:', {
          message: record.body,
          error: recordError
        });
      }
    }

    return { statusCode: 200, body: 'Traitement terminé avec succès' };
  } catch (error) {
    console.error('Erreur globale:', {
      error: error.message,
      stack: error.stack,
      event: event
    });
    
    return {
      statusCode: 500,
      body: JSON.stringify({
        message: 'Erreur de traitement',
        error: error.message
      })
    };
  }
};