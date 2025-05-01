import boto3
import json
import logging

# Configuration du logger
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Fonction Lambda pour synchroniser les utilisateurs SFTP sur les instances EC2
    lors d'un événement de cycle de vie d'autoscaling
    """
    logger.info("Événement reçu: %s", json.dumps(event))
    
    try:
        # Vérifier si c'est un événement de cycle de vie d'autoscaling
        if event.get('source') == 'aws.autoscaling' and event.get('detail-type') == 'EC2 Instance-launch Lifecycle Action':
            # Extraire les informations de l'événement
            asg_name = event['detail']['AutoScalingGroupName']
            instance_id = event['detail']['EC2InstanceId']
            lifecycle_hook_name = event['detail']['LifecycleHookName']
            lifecycle_action_token = event['detail']['LifecycleActionToken']
            
            logger.info(f"Instance {instance_id} lancée dans le groupe {asg_name}")
            
            # Attendre que l'instance soit prête
            ec2_client = boto3.client('ec2')
            waiter = ec2_client.get_waiter('instance_status_ok')
            waiter.wait(InstanceIds=[instance_id])
            
            # Exécuter le script de synchronisation sur l'instance
            ssm_client = boto3.client('ssm')
            response = ssm_client.send_command(
                InstanceIds=[instance_id],
                DocumentName='AWS-RunShellScript',
                Parameters={
                    'commands': ['/opt/sftp-autoscaling/sync_sftp_users.sh']
                },
                Comment='Synchronisation des utilisateurs SFTP'
            )
            
            command_id = response['Command']['CommandId']
            logger.info(f"Commande SSM {command_id} envoyée à l'instance {instance_id}")
            
            # Attendre que la commande soit terminée
            waiter = ssm_client.get_waiter('command_executed')
            waiter.wait(
                CommandId=command_id,
                InstanceId=instance_id
            )
            
            # Continuer le cycle de vie
            asg_client = boto3.client('autoscaling')
            asg_client.complete_lifecycle_action(
                LifecycleHookName=lifecycle_hook_name,
                AutoScalingGroupName=asg_name,
                LifecycleActionToken=lifecycle_action_token,
                LifecycleActionResult='CONTINUE'
            )
            
            logger.info(f"Cycle de vie continué pour l'instance {instance_id}")
            return {
                'statusCode': 200,
                'body': json.dumps(f'Synchronisation des utilisateurs SFTP réussie pour l\'instance {instance_id}')
            }
        else:
            logger.info("Événement ignoré: ce n'est pas un événement de cycle de vie d'autoscaling")
            return {
                'statusCode': 200,
                'body': json.dumps('Événement ignoré')
            }
    except Exception as e:
        logger.error(f"Erreur lors de la synchronisation des utilisateurs: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Erreur: {str(e)}')
        }
