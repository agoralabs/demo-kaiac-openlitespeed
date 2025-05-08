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
  ec2: new AWS.EC2(),
  sqs: new AWS.SQS(),
  ssm: new AWS.SSM()
};

// Fonction pour vérifier le statut de la commande SSM
async function waitForCommandCompletion(instanceId, commandId) {
  const maxAttempts = parseInt(process.env.SSM_MAX_ATTEMPTS || '60'); // 60 tentatives par défaut
  const delay = parseInt(process.env.SSM_RETRY_DELAY_MS || '5000'); // 5 secondes par défaut

  console.log(`Attente de la commande SSM (maxAttempts=${maxAttempts}, delay=${delay}ms)`);

  for (let attempt = 0; attempt < maxAttempts; attempt++) {
    await new Promise(resolve => setTimeout(resolve, delay));

    const result = await clients.ssm.getCommandInvocation({
      CommandId: commandId,
      InstanceId: instanceId
    }).promise();

    console.log(`Statut de la commande ${commandId} (tentative ${attempt + 1}/${maxAttempts}): ${result.Status}`);

    if (result.Status === 'Success') {
      console.log(`Commande réussie. Sortie: ${result.StandardOutputContent}`);
      return { output: result.StandardOutputContent, error: result.StandardErrorContent };
    } else if (['Failed', 'Cancelled', 'TimedOut'].includes(result.Status)) {
      throw new Error(`Échec de l'exécution de la commande: ${result.StandardErrorContent || result.Status}`);
    }
  }

  throw new Error(`Délai d'attente dépassé (${maxAttempts * delay / 1000}s) pour la commande SSM`);
}

// Fonction principale pour créer un site WordPress
async function manageWordPress(instanceId, message) {
  const command = [
    process.env.SCRIPT_COMMAND || '/home/ubuntu/manage_wordpress.sh',
    `"${message.record}.${message.domain}"`,
    `"${message.domain_folder}"`,
    `"${message.wp_db_name  || ''}"`,
    `"${message.wp_db_user  || ''}"`,
    `"${message.wp_db_password  || ''}"`,
    `"${process.env.MYSQL_DB_HOST || 'localhost'}"`,
    `"${process.env.MYSQL_ROOT_USER || 'root'}"`,
    `"${process.env.MYSQL_ROOT_PASSWORD}"`,
    `"${message.php_version || 'lsphp81'}"`,
    `"${message.wp_version || 'latest'}"`,
    `"${message.installation_method || ''}"`,
    `"${message.git_repo_url  || ''}"`,
    `"${message.git_branch  || ''}"`,
    `"${message.git_username  || ''}"`,
    `"${message.git_token  || ''}"`,
    `"${message.record  || ''}"`,
    `"${message.domain  || ''}"`,
    `"${process.env.ALB_TAG_NAME || 'Name'}"`,
    `"${process.env.ALB_TAG_VALUE}"`,
    `"${message.wp_zip_location  || ''}"`,
    `"${message.wp_db_dump_location  || ''}"`,
    `"${message.wp_source_domain  || ''}"`,
    `"${message.wp_source_domain_folder  || ''}"`,
    `"${message.wp_source_db_name  || ''}"`,
    `"${message.wp_push_location  || ''}"`,
    `"${message.ftp_user  || ''}"`,
    `"${message.ftp_pwd  || ''}"`,
    `"${message.maintenance_mode  || ''}"`,
    `"${message.lscache  || ''}"`,
    `"${message.backup_type  || ''}"`,
    `"${message.backup_location  || ''}"`
  ].join(' ');

  console.log('Exécution de la commande SSM:', command);
  
  const { Command } = await clients.ssm.sendCommand({
    InstanceIds: [instanceId],
    DocumentName: 'AWS-RunShellScript',
    Parameters: { commands: [command] },
    TimeoutSeconds: 300
  }).promise();

  // Attendre la fin de l'exécution
  await waitForCommandCompletion(instanceId, Command.CommandId);

  return {
    statusCode: 200,
    body: JSON.stringify('WordPress site created successfully')
  };
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

        console.log(`Instance EC2 trouvée: ${instanceId}`);

        console.log(`Exécuter la commande appropriée ${message.command}`);
        // Exécuter la commande appropriée
        await manageWordPress(instanceId, message);

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