# Add values
# Use the AMI of the custom Ec2 image you previously created
imageid                = "ami-0d6706b99f85f1a04"
# Use t2.micro for the AWS Free Tier
instance-type          = "t2.micro"
key-name               = "module-05-key"
vpc_security_group_ids = "sg-07e6e7579338a74ac"
tag-name               = "module-06"
user-sns-topic         = "tayb-module06-updates"
elb-name               = "tayb-m6-elb"
tg-name                = "tayb-m6-tg"
asg-name               = "tayb-m6-asg"
desired                = 3
min                    = 2
max                    = 5
number-of-azs          = 3
region                 = "us-east-1"
raw-s3-bucket          = "tayb-module06-raw-bucket-20260927"
finished-s3-bucket     = "tayb-module06-finished-bucket-20260927"
sqs-name               = "tayb-module06-sqs"

dynamodb-name          = "company"
