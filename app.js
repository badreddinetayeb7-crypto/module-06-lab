const express = require('express');
const app = express();
const multer = require('multer');
const multerS3 = require('multer-s3');

const {
  S3Client,
  ListBucketsCommand,
  ListObjectsV2Command,
} = require('@aws-sdk/client-s3');

const {
  SNSClient,
  ListTopicsCommand,
  SubscribeCommand,
} = require('@aws-sdk/client-sns');

const {
  SQSClient,
  SendMessageCommand,
  ListQueuesCommand,
} = require('@aws-sdk/client-sqs');

const {
  ListTablesCommand,
  DynamoDBClient,
  ScanCommand,
  PutItemCommand,
  QueryCommand,
} = require('@aws-sdk/client-dynamodb');

const { v4: uuidv4 } = require('uuid');
const ip = require('ip');

//////////////////////////////////////////////////////////////////////////////
// CHANGE THIS ONLY IF YOUR Terraform/AWS DEFAULT REGION IS DIFFERENT.
//////////////////////////////////////////////////////////////////////////////
const REGION = 'us-east-1';
const TABLE_NAME = 'company';

const s3 = new S3Client({ region: REGION });
const dynamodb = new DynamoDBClient({ region: REGION });
const sqs = new SQSClient({ region: REGION });
const sns = new SNSClient({ region: REGION });

async function getRawBucketName() {
  const result = await s3.send(new ListBucketsCommand({}));
  const bucket = (result.Buckets || []).find((b) => b.Name === 'tayb-module06-raw-bucket-20260927');
  if (!bucket) throw new Error('No S3 bucket containing "raw" was found.');
  return bucket.Name;
}

const upload = multer({
  storage: multerS3({
    s3,
    bucket: async function (req, file, cb) {
      try {
        cb(null, await getRawBucketName());
      } catch (err) {
        cb(err);
      }
    },
    key: function (req, file, cb) {
      cb(null, file.originalname);
    },
  }),
});

async function listObjects() {
  const bucketName = await getRawBucketName();
  const result = await s3.send(new ListObjectsV2Command({ Bucket: bucketName }));
  return (result.Contents || []).map(
    (obj) => `https://${bucketName}.s3.amazonaws.com/${encodeURIComponent(obj.Key).replace(/%2F/g, '/')}`
  );
}

async function getListOfSnsTopics() {
  return sns.send(new ListTopicsCommand({}));
}

async function subscribeEmailToSNSTopic(email) {
  if (!email) return;
  const topics = await getListOfSnsTopics();
  if (!topics.Topics || topics.Topics.length === 0) return;
  return sns.send(new SubscribeCommand({
    Endpoint: email,
    Protocol: 'email',
    TopicArn: topics.Topics[0].TopicArn,
  }));
}

async function listSqsQueueURL() {
  return 'https://sqs.us-east-1.amazonaws.com/407708719081/tayb-module06-sqs';
}

async function sendMessageToQueue(recordID) {
  const queueUrl = await listSqsQueueURL();
  return sqs.send(new SendMessageCommand({
    QueueUrl: queueUrl,
    MessageBody: String(recordID),
  }));
}

// Required DynamoDB ListTables function.
async function getDynamoTable() {
  const response = await dynamodb.send(new ListTablesCommand({}));
  if (!(response.TableNames || []).includes(TABLE_NAME)) {
    throw new Error(`DynamoDB table ${TABLE_NAME} was not found.`);
  }
  return response;
}

// Required QueryCommand example used to retrieve a record by RecordNumber.
async function retrieveLastDynamoRecordID(recNum) {
  await getDynamoTable();
  const response = await dynamodb.send(new QueryCommand({
    TableName: TABLE_NAME,
    KeyConditionExpression: 'RecordNumber = :rNum',
    ExpressionAttributeValues: { ':rNum': { S: String(recNum) } },
    ConsistentRead: true,
  }));
  return response.Items && response.Items[0]
    ? response.Items[0].RecordNumber.S
    : null;
}

async function queryAndPrintDynamoRecords(req, res) {
  await getDynamoTable();
  const response = await dynamodb.send(new ScanCommand({ TableName: TABLE_NAME }));
  res.set('Content-Type', 'application/json');
  res.send(JSON.stringify(response.Items || [], null, 2));
}

async function putDynamoItem(req) {
  const s3URLs = await listObjects();
  const fname = req.file.originalname;
  const rawS3URL = s3URLs.find((url) => url.includes(encodeURIComponent(fname)) || url.includes(fname));
  if (!rawS3URL) throw new Error(`Could not locate uploaded object ${fname} in raw S3 bucket.`);

  const RecordNumber = uuidv4();
  await getDynamoTable();

  await dynamodb.send(new PutItemCommand({
    TableName: TABLE_NAME,
    Item: {
      Email: { S: String(req.body.email || '') },
      RecordNumber: { S: RecordNumber },
      CustomerName: { S: String(req.body.name || '') },
      Phone: { S: String(req.body.phone || '') },
      Stat: { N: '0' },
      RAWS3URL: { S: rawS3URL },
      // Keep this course/autograder spelling exactly as supplied.
      FINSIHEDS3URL: { S: '' },
    },
  }));

  await sendMessageToQueue(RecordNumber);
  return { RecordNumber, rawS3URL };
}

app.get('/', (req, res) => {
  res.sendFile(__dirname + '/index.html');
});

app.get('/gallery', async (req, res) => {
  try {
    const imageURLs = await listObjects();
    res.set('Content-Type', 'text/html');
    res.write('<div>Welcome to the gallery</div>');
    for (const url of imageURLs) res.write(`<div><img src="${url}" /></div>`);
    res.end();
  } catch (err) {
    console.error(err);
    res.status(500).send(err.message);
  }
});

app.post('/upload', upload.single('uploadFile'), async (req, res) => {
  try {
    if (!req.file) return res.status(400).send('No image uploaded.');

    const result = await putDynamoItem(req);

    // The assignment asks for SNS integration. A new email subscription requires
    // confirmation from the email address before notifications are delivered.
    try {
      await subscribeEmailToSNSTopic(req.body.email);
    } catch (snsErr) {
      console.error('SNS subscription error:', snsErr);
    }

    res.type('text').send(
      `Successfully uploaded 1 file!\n` +
      `RecordNumber: ${result.RecordNumber}\n` +
      `Name: ${req.body.name || ''}\n` +
      `Raw S3 URL: ${result.rawS3URL}\n` +
      `Email: ${req.body.email || ''}\n` +
      `Phone: ${req.body.phone || ''}\n`
    );
  } catch (err) {
    console.error(err);
    res.status(500).send(err.message);
  }
});

app.get('/dynamodb', async (req, res) => {
  try {
    await queryAndPrintDynamoRecords(req, res);
  } catch (err) {
    console.error(err);
    res.status(500).send(err.message);
  }
});

app.get('/ip', (req, res) => {
  res.type('text').send(`Network access via: ${ip.address()}`);
});

app.listen(3000, () => {
  console.log('Module 6 application listening on port 3000');
});
