require('dotenv').config();
const { SQSClient } = require('@aws-sdk/client-sqs');
const { Route53Client, ChangeResourceRecordSetsCommand, ListHostedZonesByNameCommand } = require('@aws-sdk/client-route-53');
const axios = require('axios');

// Clients AWS
const sqs = new SQSClient({ region: process.env.AWS_REGION_APP });
const route53 = new Route53Client({ region: process.env.AWS_REGION_APP });

// Configuration Mailcow
const MAILCOW_HOST = `https://${process.env.MAILCOW_HOST}`;
const API_KEY = process.env.MAILCOW_API_KEY;

// Fonction handler Lambda
exports.handler = async (event) => {
  console.log('📨 Event received:', JSON.stringify(event));

  for (const record of event.Records) {
    try {
      const body = JSON.parse(record.body);
      const { domain, userId, command, localPart, mailboxPwd } = body;
      const commands = ['CREATE_DOMAIN', 'DELETE_DOMAIN', 'CREATE_MAILBOX', 'DELETE_MAILBOX'];

      if (!commands.includes(command)) {
        throw new Error(`Invalid command: ${command}. Must be one of ${commands}`);
      }

      console.log(`Processing domain "${domain}" for user ${userId} (${command})`);

      if (command === 'CREATE_DOMAIN') {
        // 1. Création du domaine dans Mailcow
        await createMailcowDomain(domain);
        
        // 2. Génération du DKIM
        await generateDKIM(domain);
        
        // 3. Récupération du DKIM
        const dkimRecord = await getDKIM(domain);
        
        // 4. Création des enregistrements DNS
        await createDNSRecords(domain, dkimRecord);

        console.log(`✅ Domain "${domain}" created successfully`);
      }
      
      if (command === 'DELETE_DOMAIN') {
        // 1. Suppression des enregistrements DNS
        await deleteDNSRecords(domain);
        
        // 2. Suppression du domaine Mailcow
        await deleteMailcowDomain(domain);

        console.log(`✅ Domain "${domain}" deleted successfully`);
      }

      if (command === 'CREATE_MAILBOX') {
        // 1. Création de la mailbox
        await createMailcowMailbox(domain, localPart, mailboxPwd);

        console.log(`✅ Mailbox "${localPart}@${domain}" created successfully`);
      }

      if (command === 'DELETE_MAILBOX') {
        // 1. Suppression de la mailbox
        await deleteMailcowMailbox(domain, localPart);

        console.log(`✅ Mailbox "${localPart}@${domain}" deleted successfully`);
      }


    } catch (error) {
      console.error('❌ Error processing domain:', error.message);
      throw error;
    }
  }

  return { statusCode: 200, body: JSON.stringify('Processed successfully') };
};

// capitalize first letter
function capitalizeWord(word) {
  if (!word) return word; // Gestion des valeurs nulles/vides
  return word.charAt(0).toUpperCase() + word.slice(1).toLowerCase();
}

// Fonctions pour la création de l'adresse mail
async function createMailcowMailbox(domain, localPart, mailboxPwd) {

  if (!domain || !localPart || !mailboxPwd) {
    throw new Error('Missing required parameters');
  }

  try {    

    const email = `${localPart}@${domain}`;

    const payload = {
      local_part: localPart,
      domain: domain,
      password: mailboxPwd,
      password2: mailboxPwd,
      name: capitalizeWord(localPart),
      quota: 3072, // 3GB en MB
      active: '1', // 1 pour actif, 0 pour inactif
      force_pw_update: '1', // Force le changement de mot de passe
      tls_enforce_in: '1', // Force TLS entrant
      tls_enforce_out: '1', // Force TLS sortant
      description: "Créé via AWS Lambda"
    };
  
    const response = await retryRequest(
      () => axios.post(
        `${MAILCOW_HOST}/api/v1/add/mailbox`,
        payload,
        {
          headers: {
            'X-API-Key': API_KEY,
            'Content-Type': 'application/json',
          }
        }
      ),
      3,
      5000
    );
  
    console.log(`Email ${email} created successfully`, response.data);
  
    return response;

  } catch (error) {
    console.error('Error creating mailbox:', error.response?.data || error.message);
    
    return {
        statusCode: error.response?.status || 500,
        body: JSON.stringify({
            success: false,
            error: error.response?.data || error.message
        })
    };
  }

}

// Fonctions pour la suppression de l'adresse email
async function deleteMailcowMailbox(domain, localPart) {

  if (!domain || !localPart) {
    throw new Error('Missing required parameters');
  }

  try {
    const email = `${localPart}@${domain}`;

    const response = await retryRequest(
      () => axios.post(
        `${MAILCOW_HOST}/api/v1/delete/mailbox`,
        { email }, // Corps de la requête avec l'attribut domain
        {
          headers: {
            'X-API-Key': API_KEY,
            'Content-Type': 'application/json' // Important
          }
        }
      ),
      3,
      5000
    );
  
    console.log(`Email ${email} deleted successfully`, response.data);

    return response;

  } catch (error) {
    console.error('Error deleting mailbox:', error.response?.data || error.message);
    
    // Gestion spécifique des erreurs 404 (email non trouvé)
    if (error.response?.status === 404) {
        return {
            statusCode: 200,
            body: JSON.stringify({
                success: true,
                message: `Email ${email} was already deleted or doesn't exist`
            })
        };
    }
    
    return {
        statusCode: error.response?.status || 500,
        body: JSON.stringify({
            success: false,
            error: error.response?.data || error.message
        })
    };
  } 

}

// Fonctions pour la création du domaine
async function createMailcowDomain(domain) {

  const response = await retryRequest(
    () => axios.post(
      `${MAILCOW_HOST}/api/v1/add/domain`,
      { 
        domain,
        description: "Créé via AWS Lambda"
      },
      {
        headers: {
          'X-API-Key': API_KEY,
          'Content-Type': 'application/json',
        }
      }
    ),
    3,
    5000
  );

  console.log(`Domain "${domain}" created in Mailcow`, response.data);
  return response;
}

async function generateDKIM(domain) {
  const response = await retryRequest(
    () => axios.post(
      `${MAILCOW_HOST}/api/v1/add/dkim/${domain}`,
      null,
      {
        headers: {
          'X-API-Key': API_KEY
        }
      }
    ),
    3,
    5000
  );

  console.log(`DKIM generated for domain "${domain}"`, response.data);
  return response;
}

async function getDKIM(domain) {
  const response = await retryRequest(
    () => axios.get(
      `${MAILCOW_HOST}/api/v1/get/dkim/${domain}`,
      {
        headers: {
          'X-API-Key': API_KEY
        }
      }
    ),
    3,
    5000
  );

  const dkimRecord = response.data.dkim_txt;
  console.log(`DKIM record for "${domain}":`, dkimRecord);
  return dkimRecord;
}

async function createDNSRecords(domain, dkimRecord) {
  const zoneId = await getHostedZoneId(domain);
  const mailHostname = process.env.MAILCOW_HOST;
  
  const dkimChunks = chunkString(dkimRecord, 255);

  const params = {
    ChangeBatch: {
      Changes: getDNSRecordChanges(domain, mailHostname, dkimChunks, 'CREATE')
    },
    HostedZoneId: zoneId
  };

  const command = new ChangeResourceRecordSetsCommand(params);
  const response = await route53.send(command);
  console.log(`DNS records created for "${domain}"`, response);
  return response;
}

// Fonctions pour la suppression
async function deleteMailcowDomain(domain) {
  const response = await retryRequest(
    () => axios.post(
      `${MAILCOW_HOST}/api/v1/delete/domain`,
      { domain: domain }, // Corps de la requête avec l'attribut domain
      {
        headers: {
          'X-API-Key': API_KEY,
          'Content-Type': 'application/json' // Important
        }
      }
    ),
    3,
    5000
  );

  console.log(`Domain "${domain}" deleted from Mailcow`, response.data);
  return response;
}

async function deleteDNSRecords(domain) {
  const zoneId = await getHostedZoneId(domain);
  const mailHostname = process.env.MAILCOW_HOST;
  
  // On récupère le DKIM avant suppression pour construire les bons enregistrements
  let dkimRecord;
  try {
    dkimRecord = await getDKIM(domain);
  } catch (error) {
    console.warn(`Could not retrieve DKIM for deletion (might be already gone): ${error.message}`);
    dkimRecord = ''; // Valeur par défaut
  }
  
  const dkimChunks = chunkString(dkimRecord, 255);

  const params = {
    ChangeBatch: {
      Changes: getDNSRecordChanges(domain, mailHostname, dkimChunks, 'DELETE')
    },
    HostedZoneId: zoneId
  };

  const command = new ChangeResourceRecordSetsCommand(params);
  const response = await route53.send(command);
  console.log(`DNS records deleted for "${domain}"`, response);
  return response;
}

// Fonctions utilitaires
async function getHostedZoneId(domain) {
  const command = new ListHostedZonesByNameCommand({
    DNSName: domain
  });
  
  const response = await route53.send(command);
  if (!response.HostedZones || response.HostedZones.length === 0) {
    throw new Error(`No hosted zone found for domain: ${domain}`);
  }
  
  const zoneId = response.HostedZones[0].Id.split('/').pop();
  console.log(`Found hosted zone ID for "${domain}":`, zoneId);
  return zoneId;
}

function chunkString(str, size) {
  const chunks = [];
  for (let i = 0; i < str.length; i += size) {
    chunks.push(str.substring(i, i + size));
  }
  return chunks;
}

async function retryRequest(requestFn, attempts, delayMs) {
  for (let i = 0; i < attempts; i++) {
    try {
      return await requestFn();
    } catch (error) {
      if (i === attempts - 1) throw error;
      console.log(`Attempt ${i + 1} failed, retrying in ${delayMs}ms...`);
      await new Promise(resolve => setTimeout(resolve, delayMs));
    }
  }
}

function getDNSRecordChanges(domain, mailHostname, dkimChunks, action) {
  if (!['CREATE', 'DELETE'].includes(action)) {
    throw new Error(`Invalid action: ${action}. Must be CREATE or DELETE`);
  }

  const changes = [
    // MX Record
    {
      Action: action === 'CREATE' ? 'UPSERT' : 'DELETE',
      ResourceRecordSet: {
        Name: domain,
        Type: "MX",
        TTL: 3600,
        ResourceRecords: [{ Value: `10 ${mailHostname}.` }]
      }
    },
    // Autodiscover CNAME
    {
      Action: action === 'CREATE' ? 'UPSERT' : 'DELETE',
      ResourceRecordSet: {
        Name: `autodiscover.${domain}`,
        Type: "CNAME",
        TTL: 3600,
        ResourceRecords: [{ Value: mailHostname }]
      }
    },
    // Autoconfig CNAME
    {
      Action: action === 'CREATE' ? 'UPSERT' : 'DELETE',
      ResourceRecordSet: {
        Name: `autoconfig.${domain}`,
        Type: "CNAME",
        TTL: 3600,
        ResourceRecords: [{ Value: mailHostname }]
      }
    },
    // SPF TXT
    {
      Action: action === 'CREATE' ? 'UPSERT' : 'DELETE',
      ResourceRecordSet: {
        Name: domain,
        Type: "TXT",
        TTL: 3600,
        ResourceRecords: [{ Value: `"v=spf1 mx a:${mailHostname} -all"` }]
      }
    },
    // DKIM TXT
    {
      Action: action === 'CREATE' ? 'UPSERT' : 'DELETE',
      ResourceRecordSet: {
        Name: `dkim._domainkey.${domain}`,
        Type: "TXT",
        TTL: 3600,
        ResourceRecords: dkimChunks.map(chunk => ({ Value: `"${chunk}"` }))
      }
    },
    // DMARC TXT
    {
      Action: action === 'CREATE' ? 'UPSERT' : 'DELETE',
      ResourceRecordSet: {
        Name: `_dmarc.${domain}`,
        Type: "TXT",
        TTL: 3600,
        ResourceRecords: [{ Value: `"v=DMARC1; p=none; rua=mailto:postmaster@${domain}"` }]
      }
    },
    // SRV Record
    {
      Action: action === 'CREATE' ? 'UPSERT' : 'DELETE',
      ResourceRecordSet: {
        Name: `_autodiscover._tcp.${domain}`,
        Type: "SRV",
        TTL: 3600,
        ResourceRecords: [{ Value: `10 10 443 ${mailHostname}.` }]
      }
    }
  ];

  return changes;
}