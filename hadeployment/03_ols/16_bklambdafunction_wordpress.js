const AWS = require('aws-sdk');
const { Route53, ELBv2, EC2, SQS, SSM } = AWS;

const route53 = new Route53();
const elbv2 = new ELBv2();
const ec2 = new EC2();
const sqs = new SQS();
const ssm = new SSM();

// Fonction pour trouver la zone hébergée
async function getHostedZoneId(domain) {
    const hostedZones = await route53.listHostedZonesByName({
        DNSName: domain
    }).promise();
    
    if (!hostedZones.HostedZones || hostedZones.HostedZones.length === 0) {
        throw new Error(`Aucune zone hébergée trouvée pour le domaine : ${domain}`);
    }
    
    const zone = hostedZones.HostedZones[0];
    return zone.Id.split('/').pop();
}

// Fonction pour trouver l'ALB par tag
async function findAlbByTag(tagName, tagValue) {
    const albs = await elbv2.describeLoadBalancers().promise();
    
    for (const alb of albs.LoadBalancers) {
        const tags = await elbv2.describeTags({
            ResourceArns: [alb.LoadBalancerArn]
        }).promise();
        
        const foundTag = tags.TagDescriptions[0].Tags.find(
            t => t.Key === tagName && t.Value === tagValue
        );
        
        if (foundTag) return alb;
    }
    
    throw new Error(`ALB avec tag ${tagName}=${tagValue} non trouvé`);
}

// Fonction pour créer le site WordPress
async function createWordPress(instanceId, message) {
    const {
        domain,
        domain_folder,
        wp_db_name,
        wp_db_user,
        wp_db_password,
        php_version = 'lsphp81',
        wp_version = 'latest'
    } = message;

    const command = [
        process.env.SCRIPT_COMMAND || '/home/ubuntu/deploy_wordpress.sh',
        `"${domain}"`,
        `"${domain_folder}"`,
        `"${wp_db_name}"`,
        `"${wp_db_user}"`,
        `"${wp_db_password}"`,
        `"${process.env.MYSQL_DB_HOST}"`,
        `"${process.env.MYSQL_ROOT_USER}"`,
        `"${process.env.MYSQL_ROOT_PASSWORD}"`,
        `"${php_version}"`,
        `"${wp_version}"`
    ].join(' ');

    await ssm.sendCommand({
        InstanceIds: [instanceId],
        DocumentName: 'AWS-RunShellScript',
        Parameters: { commands: [command] },
        TimeoutSeconds: 300
    }).promise();

    // Configurer le DNS
    const alb = await findAlbByTag(process.env.ALB_TAG_NAME || 'Name', process.env.ALB_TAG_VALUE);
    const hostedZoneId = await getHostedZoneId(domain);
    
    await route53.changeResourceRecordSets({
        HostedZoneId: hostedZoneId,
        ChangeBatch: {
            Changes: [{
                Action: 'UPSERT',
                ResourceRecordSet: {
                    Name: domain,
                    Type: 'A',
                    AliasTarget: {
                        HostedZoneId: 'Z35SXDOTRQ7X7K', // Zone ALB standard
                        DNSName: alb.DNSName,
                        EvaluateTargetHealth: false
                    }
                }
            }]
        }
    }).promise();
}

// Fonction pour supprimer le site WordPress
async function deleteWordPress(instanceId, message) {
    const { domain, domain_folder, wp_db_name } = message;

    // 1. Exécuter le script de suppression
    const deleteCommand = [
        process.env.DELETE_SCRIPT_COMMAND || '/home/ubuntu/delete_wordpress.sh',
        `"${domain}"`,
        `"${domain_folder}"`,
        `"${wp_db_name}"`,
        `"${process.env.MYSQL_ROOT_USER}"`,
        `"${process.env.MYSQL_ROOT_PASSWORD}"`
    ].join(' ');

    await ssm.sendCommand({
        InstanceIds: [instanceId],
        DocumentName: 'AWS-RunShellScript',
        Parameters: { commands: [deleteCommand] },
        TimeoutSeconds: 300
    }).promise();

    // 2. Supprimer l'enregistrement DNS
    try {
        const hostedZoneId = await getHostedZoneId(domain);
        await route53.changeResourceRecordSets({
            HostedZoneId: hostedZoneId,
            ChangeBatch: {
                Changes: [{
                    Action: 'DELETE',
                    ResourceRecordSet: {
                        Name: domain,
                        Type: 'A',
                        AliasTarget: {
                            HostedZoneId: 'Z35SXDOTRQ7X7K',
                            DNSName: (await findAlbByTag(process.env.ALB_TAG_NAME || 'Name', process.env.ALB_TAG_VALUE)).DNSName,
                            EvaluateTargetHealth: false
                        }
                    }
                }]
            }
        }).promise();
    } catch (error) {
        console.error("Erreur lors de la suppression DNS:", error);
    }
}

exports.handler = async (event) => {
    try {
        // Configuration
        const {
            EC2_TAG_NAME = 'Name',
            EC2_TAG_VALUE
        } = process.env;

        for (const record of event.Records) {
            const message = JSON.parse(record.body);
            const { command } = message;

            if (!['CREATE_WP', 'DELETE_WP'].includes(command)) {
                throw new Error(`Commande invalide: ${command}`);
            }

            // Trouver l'instance EC2
            const ec2Data = await ec2.describeInstances({
                Filters: [{ Name: `tag:${EC2_TAG_NAME}`, Values: [EC2_TAG_VALUE] }]
            }).promise();
            
            const instanceId = ec2Data.Reservations?.[0]?.Instances?.[0]?.InstanceId;
            if (!instanceId) throw new Error('Instance EC2 non trouvée');

            // Exécuter la commande appropriée
            if (command === 'CREATE_WP') {
                await createWordPress(instanceId, message);
                console.log(`Site WordPress créé pour ${message.domain}`);
            } else {
                await deleteWordPress(instanceId, message);
                console.log(`Site WordPress supprimé pour ${message.domain}`);
            }

            // Supprimer le message SQS
            await sqs.deleteMessage({
                QueueUrl: record.eventSourceARN,
                ReceiptHandle: record.receiptHandle
            }).promise();
        }

        return { statusCode: 200, body: 'Opération réussie' };
    } catch (error) {
        console.error('Erreur:', error);
        return {
            statusCode: 500,
            body: JSON.stringify({
                message: 'Échec du traitement',
                error: error.message,
                stack: process.env.DEBUG ? error.stack : undefined
            })
        };
    }
};