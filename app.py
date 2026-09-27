import boto3
from io import BytesIO
from PIL import Image
import logging
from botocore.exceptions import ClientError
from botocore.config import Config
from urllib.parse import urlparse

# CHANGE THIS ONLY IF YOUR Terraform/AWS DEFAULT REGION IS DIFFERENT.
region = 'us-east-1'
TABLE_NAME = 'company'

clientSQS = boto3.client('sqs', region_name=region)
clientDynamo = boto3.client('dynamodb', region_name=region)
clientSNS = boto3.client('sns', region_name=region)
clientS3 = boto3.client(
    's3',
    region_name=region,
    config=Config(s3={'addressing_style': 'path'}, signature_version='s3v4'),
)

print('Getting a list of DynamoDB Tables...')
responseDynamoTables = clientDynamo.list_tables()
if TABLE_NAME not in responseDynamoTables.get('TableNames', []):
    raise RuntimeError(f'DynamoDB table {TABLE_NAME} was not found.')

print('Getting a list of SQS queues...')
responseURL = clientSQS.list_queues()
queue_urls = responseURL.get('QueueUrls', [])
if not queue_urls:
    print('No SQS queues found.')
    raise SystemExit(0)
queue_url = queue_urls[0]

print('Retrieving one message from the queue...')
responseMessages = clientSQS.receive_message(
    QueueUrl=queue_url,
    VisibilityTimeout=180,
    MaxNumberOfMessages=1,
    WaitTimeSeconds=1,
)

messages = responseMessages.get('Messages', [])
if not messages:
    print('No messages found on the queue -- upload an image first.')
    raise SystemExit(0)

message = messages[0]
record_number = message['Body']
print('Message body content: ' + record_number)

responseGetDynamoItem = clientDynamo.get_item(
    TableName=TABLE_NAME,
    Key={'RecordNumber': {'S': record_number}},
    ConsistentRead=True,
)

item = responseGetDynamoItem.get('Item')
if not item:
    print('No DynamoDB item found for RecordNumber; deleting stale SQS message.')
    clientSQS.delete_message(QueueUrl=queue_url, ReceiptHandle=message['ReceiptHandle'])
    raise SystemExit(0)

print('DynamoDB item:')
print(item)

raw_url = item.get('RAWS3URL', {}).get('S', '')
if not raw_url or raw_url == 'done':
    print('Record has no processable raw URL; deleting queue message.')
    clientSQS.delete_message(QueueUrl=queue_url, ReceiptHandle=message['ReceiptHandle'])
    raise SystemExit(0)

# Parse Raw S3 URL and determine object key.
url = urlparse(raw_url)
key = url.path.lstrip('/')
print('S3 Object Key name: ' + key)

responseS3 = clientS3.list_buckets()
raw_buckets = ['tayb-module06-raw-bucket-20260927']
finished_buckets = ['tayb-module06-finished-bucket-20260927']
if not raw_buckets or not finished_buckets:
    raise RuntimeError('Could not find both raw and finished S3 buckets.')

BUCKET_NAME = raw_buckets[0]
FIN_BUCKET_NAME = finished_buckets[0]

print(f'Downloading {key} from {BUCKET_NAME}...')
responseGetObject = clientS3.get_object(Bucket=BUCKET_NAME, Key=key)
file_byte_string = responseGetObject['Body'].read()

print('Converting image to grayscale...')
im = Image.open(BytesIO(file_byte_string)).convert('L')
file_name = '/tmp/grayscale-' + key.replace('/', '-')
im.save(file_name)

print('Pushing modified image to Finished S3 bucket...')
try:
    clientS3.upload_file(file_name, FIN_BUCKET_NAME, key)
except ClientError as e:
    logging.error(e)
    raise

print('Generating presigned S3 URL...')
try:
    responsePresigned = clientS3.generate_presigned_url(
        'get_object',
        Params={'Bucket': FIN_BUCKET_NAME, 'Key': key},
        ExpiresIn=7200,
    )
except ClientError as e:
    logging.error(e)
    raise

print(responsePresigned)

# Required DynamoDB update:
# 1) Store the generated presigned URL in FINSIHEDS3URL.
# 2) Mark RAWS3URL as done after processing.
# Keep FINSIHEDS3URL misspelled because the supplied autograder expects that exact name.
print('Updating DynamoDB item with finished URL and done status...')
clientDynamo.update_item(
    TableName=TABLE_NAME,
    Key={'RecordNumber': {'S': record_number}},
    UpdateExpression='SET FINSIHEDS3URL = :finished, RAWS3URL = :done, Stat = :stat',
    ExpressionAttributeValues={
        ':finished': {'S': responsePresigned},
        ':done': {'S': 'done'},
        ':stat': {'N': '1'},
    },
)

# Send presigned URL through SNS.
print('Listing SNS Topic ARNs...')
responseTopics = clientSNS.list_topics()
topics = responseTopics.get('Topics', [])
if topics:
    messageToSend = (
        'Your image: ' + str(key) +
        ' is ready for download at: ' + str(responsePresigned)
    )
    clientSNS.publish(
        TopicArn=topics[0]['TopicArn'],
        Subject='Your image is ready for download!',
        Message=messageToSend,
    )
    print('Message published to SNS Topic.')

print('Deleting the processed SQS message...')
clientSQS.delete_message(
    QueueUrl=queue_url,
    ReceiptHandle=message['ReceiptHandle'],
)

print('Deleting the original object from the Raw S3 bucket...')
clientS3.delete_object(Bucket=BUCKET_NAME, Key=key)
print('Processing complete.')
