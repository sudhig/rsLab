###########################################################################
# Author: Sudhir Gupta
# Date: 2-Jun-2019
# Version: 2.0
###########################################################################

AWSTemplateFormatVersion: 2010-09-09
Description: >-
 This AWS CloudFormation template will create following resources:
 VPC, 
 2 public subnets, 
 Security group whitelisting Quicksight and user specified Inbound Traffic.
 IGW, S3 EndPoint,
 Bastion host,
 Redshift Cluster with TPCDS 3TB dataset,
 IAM Role for Spectrum, WLM Queues & Custom Cluster Parameter Group,
 Different Cloudwatch alarms based on environment, 
 AWS Glue Catalog, 
 Glue Crawler creates external tables for TPCSDS 30TB dataset.
 Sample Glue Catalog/External tables for Non-Produnction environments,
 Set of Tags 

Parameters:
  VPCCIDR:
    Description: CIDR address for the VPC to be created.
    Type: String
    Default: 10.0.0.0/16
    AllowedPattern: >-
      ^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])(\/(1[6-9]|2[0-8]))$
    ConstraintDescription: CIDR block parameter must be in the form x.x.x.x/16-28
  
  PublicSubnet1:
    Description: CIDR address for VPC Public subnet to be created in AZ1.
    Type: String
    Default: 10.0.0.0/20
    AllowedPattern: >-
      ^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])(\/(1[6-9]|2[0-8]))$
    ConstraintDescription: CIDR block parameter must be in the form x.x.x.x/16-28
    
  PublicSubnet2:
    Description: CIDR address for  VPC Public subnet to be created in AZ2.
    Type: String
    Default: 10.0.16.0/20
    AllowedPattern: >-
      ^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])(\/(1[6-9]|2[0-8]))$
    ConstraintDescription: CIDR block parameter must be in the form x.x.x.x/16-28
  
  destCIDRpublic:
    Description: Destination CIDR for Public route / InternetGateway
    Type: String
    Default: 0.0.0.0/0
  
  InboundTraffic:
    Description: Allow inbound traffic to the Redshift cluster from this CIDR range.
    Type: String
    MinLength: '9'
    MaxLength: '18'
    Default: 0.0.0.0/0
    AllowedPattern: '(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})/(\d{1,2})'
    ConstraintDescription: must be a valid CIDR range of the form x.x.x.x/x.

  InstanceType:
    AllowedValues:
      - t2.small
      - t2.medium
      - t2.large
      - m4.large
      - m4.xlarge
      - m4.2xlarge
      - m4.4xlarge
      - m5.large
      - m5.xlarge
      - t3.small
      - t3.medium
    Default: m4.large
    Description: Amazon EC2 instance type for the bastion instance. t2 instance types are not supported for dedicated VPC tenancy (option below).
    Type: String

  KeyPairName:
    Description: >-
      Enter a Public/private key pair. If you do not have one in this AWS Region,
      create it before continuing
    Type: 'AWS::EC2::KeyPair::KeyName'
          
  DatabaseName:
    Description: The name of the first database to be created when the cluster is created
    Type: String
    Default: rsdev01
    AllowedPattern: '([a-z]|[0-9])+' 
    
  RedshiftClusterPort:
    Description: The port number on which the cluster accepts incoming connections.
    Type: Number
    Default: '8192'
  
  ClusterType:
    Description: The type of cluster
    Type: String
    Default: multi-node
    AllowedValues:
      - single-node
      - multi-node
    ConstraintDescription: must be single-node or multi-node.
  
  NumberOfNodes:
    Description: >-
      The number of compute nodes in the cluster. For multi-node clusters, the
      NumberOfNodes parameter must be greater than 1
    Type: Number
    Default: '2'
  
  NodeType:
    Description: The type of node to be provisioned
    Type: String
    Default: ds2.8xlarge
    AllowedValues:
      - dc2.large
      - dc2.8xlarge
      - ds2.xlarge
      - ds2.8xlarge
      - dc1.large
  
  MasterUsername:
    Description: >-
      The user name that is associated with the master user account for the
      cluster that is being created
    Type: String
    Default: rsadmin
    AllowedPattern: '([a-z])([a-z]|[0-9])*'
    ConstraintDescription: must start with a-z and contain only a-z or 0-9.
  
  MasterUserPassword:
    Description: >-
      The password that is associated with the master user account for the cluster that is being created. Example: Welcome123
    Type: String
    Default: Welcome123
    NoEcho: 'true'
    MinLength: '4'
    MaxLength: '64'
    AllowedPattern: >-
     ^(?=.*[a-z])(?=.*[A-Z])(?=.*[0-9])(?!._*[@/\\\"']).*$
    ConstraintDescription: >-
     Must contain only alphanumeric characters. Example: Welcome123
  
  Maintenancewindow:
    Description: Maintenance Window for Redshift Cluster
    Type: String
    Default: 'sat:05:00-sat:05:30'
        
  MaxConcurrentCluster:
    Description: Maximum Concurrency Scaling Redshift Clusters
    Type: String
    Default: '1'
    
  EncryptionAtRest:
    Description: >-
      Do you want to enable data encryption at rest?
    Type: String
    Default: false
    AllowedValues:
      - true
      - false
    ConstraintDescription: must be true or false.
  
  kmskey:
    Description: Existing KMS key ID
    Type: String
    Default: ''
    
  SnapshotIdentifier:
    Description: Leave it blank for new cluster. Enter Snapshot Identifier only if you want to restore from snapshot. 
    Type: String
    
  SnapshotAccountNumber:
    Description: "AWS Account number of Snapshot (Leave it blank, if snapshot is created in current AWS Account)"
    Type: String
    
  SubscriptionEmail:
    Type: String
    Description: Email address to notify when an API activity has triggered an alarm
    Default: "abc@xyz.com"
    #AllowedPattern: ^[a-zA-Z0-9_.+-]+@[a-zA-Z0-9-]+\\.[a-zA-Z0-9-.]+$
    
  S3BucketForSpectrum:
    Default: 'jwyant-tpcds'
    Type: String
    Description: Enter existing S3 Bucket contains data files for Redshift Spectrum
        
  GlueCatalogDatabase:
    Default: 'rs_catalog_db'
    Type: String
    Description: The name of the Glue Catalog database.
        
  SpectrumTableLocation:
    Default: 's3://jwyant-tpcds/optimized/30tb'
    Type: String
    Description:  >-
      Enter S3 full path contains data files for the Spectrum table.
        
  CrawlerNameSuffix:
    Type: String
    Default: 'tpcds_30tb'
    Description:  Name of the Glue Crawler to be created for sample S3 bucket for non-Prod Environment
        
  GlueTablePrefix:
    Type: String
    Default: 't_'
    Description: Enter prefix for the table created by Glue crawler
  
  TagName:
    Type: String
    Description: Unique friendly name as required by the your company tagging strategy document and will be added to tag.
    Default: 'RedshiftLab'

  TagEnvironment:
    Type: String
    AllowedValues:
      - Development
      - Production
    Description: The environment key is used to designate the production level of the associated AWS resource.
    Default: Development

Metadata:
  AWS::CloudFormation::Interface:
    ParameterGroups:
      -
        Label:
          default: Environment of Application
        Parameters:
          - TagEnvironment
          - TagName
      -
        Label:
          default: VPC / Network Parameters
        Parameters:
          - VPCCIDR
          - PublicSubnet1
          - PublicSubnet2
          - destCIDRpublic
          - KeyPairName
          - InstanceType 
      -
        Label:
          default: Redshift Cluster Parameters
        Parameters:
          - ClusterType
          - NodeType
          - NumberOfNodes
          - RedshiftClusterPort
          - DatabaseName
          - MasterUsername
          - MasterUserPassword
          - InboundTraffic      
      -
        Label:
          default: Redshift additional/optional Parameters
        Parameters:
          - MaxConcurrentCluster
          - SnapshotIdentifier
          - SnapshotAccountNumber
          - SubscriptionEmail
          - EncryptionAtRest
          - kmskey
          - Maintenancewindow            
      -
        Label:
          default: Glue Catalog and Redshift Spectrum configuration Parameters
        Parameters:
          - S3BucketForSpectrum
          - GlueCatalogDatabase
          - CrawlerNameSuffix
          - SpectrumTableLocation
          - GlueTablePrefix

Mappings:
  AWSAMIRegionMap:
    AMI:
      AMZNLINUXHVM: ami-08ae6fd98c78bcf15
    us-east-1:
      AMZNLINUXHVM: ami-08ae6fd98c78bcf15
    us-east-2:
      AMZNLINUXHVM: ami-0f1fb8b0de77e7a31
    us-west-1:
      AMZNLINUXHVM: ami-02a398f3c1a7adde7
    us-west-2:
      AMZNLINUXHVM: ami-04babd89291f34a40
    ap-south-1:
      AMZNLINUXHVM: ami-0959c7162a6fb3007
    eu-west-1:
      AMZNLINUXHVM: ami-04025414f699b80b1
  LinuxAMINameMap:
    Amazon-Linux-HVM:
      Code: AMZNLINUXHVM

Conditions:
  IsMultiNodeCluster: !Equals [!Ref ClusterType, 'multi-node']
  IsEncryptionAtRest: !Equals [!Ref EncryptionAtRest, 'true']
  IsSnapshotSpecified:
    Fn::Not:
    - Fn::Equals:
      - ''
      - Ref: SnapshotIdentifier
  IsSnapshotAccountSpecified:
    Fn::Not:
    - Fn::Equals:
      - ''
      - Ref: SnapshotAccountNumber

Resources:
  VPC:
    Type: 'AWS::EC2::VPC'
    Properties:
      InstanceTenancy: default
      EnableDnsSupport: true
      EnableDnsHostnames: true
      CidrBlock: !Ref VPCCIDR
      Tags:
        - 
          Key: Name
          Value: !Join [ "-", [ !Ref TagName, "VPC" ] ]
        -
          Key: Environment
          Value: !Ref TagEnvironment
          
  VPCPublicSubnet1:
    Type: 'AWS::EC2::Subnet'
    Properties:
      VpcId: !Ref VPC
      AvailabilityZone: !Select 
        - '0'
        - !GetAZs ''
      CidrBlock: !Ref PublicSubnet1
      Tags:
        - Key: Name
          Value: PublicSubnet1
        - Key: Network
          Value: Public
        -
          Key: Environment
          Value: !Ref TagEnvironment

  VPCPublicSubnet2:
    Type: 'AWS::EC2::Subnet'
    Properties:
      VpcId: !Ref VPC
      AvailabilityZone: !Select 
        - '1'
        - !GetAZs ''
      CidrBlock: !Ref PublicSubnet2
      Tags:
        - Key: Name
          Value: PublicSubnet2
        - Key: Network
          Value: Public
        -
          Key: Environment
          Value: !Ref TagEnvironment  
          
  InternetGateway:
    Type: 'AWS::EC2::InternetGateway'
    Properties:
      Tags:
        - Key: Name
          Value: IGW
        -
          Key: Environment
          Value: !Ref TagEnvironment
          
  AttachGateway:
    Type: 'AWS::EC2::VPCGatewayAttachment'
    Properties:
      VpcId: !Ref VPC
      InternetGatewayId: !Ref InternetGateway
      
  PublicRoutetable:
    Type: 'AWS::EC2::RouteTable'
    Properties:
      VpcId: !Ref VPC
      Tags:
        - Key: Application
          Value: VPC
        - Key: Name
          Value: PublicRoutetable
        - Key: Network
          Value: Private
        -
          Key: Environment
          Value: !Ref TagEnvironment
          
  Publicroute:
    Type: 'AWS::EC2::Route'
    DependsOn: InternetGateway
    Properties:
      RouteTableId: !Ref PublicRoutetable
      DestinationCidrBlock: !Ref destCIDRpublic
      GatewayId: !Ref InternetGateway
      
  Public1RTAssoc:
    Type: 'AWS::EC2::SubnetRouteTableAssociation'
    Properties:
      SubnetId: !Ref VPCPublicSubnet1
      RouteTableId: !Ref PublicRoutetable
  Public2RTAssoc:
    Type: 'AWS::EC2::SubnetRouteTableAssociation'
    Properties:
      SubnetId: !Ref VPCPublicSubnet2
      RouteTableId: !Ref PublicRoutetable
      
  S3Endpoint:
    Type: AWS::EC2::VPCEndpoint
    Properties:
        PolicyDocument:
            Version: 2012-10-17
            Statement:
                - Effect: Allow
                  Principal: '*'
                  Action:
                    - 's3:*'
                  Resource: '*'
        RouteTableIds:
            - !Ref PublicRoutetable
        ServiceName:  !Join [ "", ["com.amazonaws.",!Ref 'AWS::Region',".s3"] ]
        VpcId: !Ref VPC
  
  SecurityGroup:
    Type: 'AWS::EC2::SecurityGroup'
    Properties:
      VpcId: !Ref VPC
      GroupDescription: Management Group
      SecurityGroupIngress:
        - IpProtocol: tcp
          FromPort: !Ref RedshiftClusterPort
          ToPort: !Ref RedshiftClusterPort
          CidrIp: 52.15.247.160/27
        - IpProtocol: tcp
          FromPort: !Ref RedshiftClusterPort
          ToPort: !Ref RedshiftClusterPort
          CidrIp: 52.23.63.224/27
        - IpProtocol: tcp
          FromPort: !Ref RedshiftClusterPort
          ToPort: !Ref RedshiftClusterPort
          CidrIp: 54.70.204.128/27
        - IpProtocol: tcp
          FromPort: !Ref RedshiftClusterPort
          ToPort: !Ref RedshiftClusterPort
          CidrIp: 52.210.255.224/27
        - IpProtocol: tcp
          FromPort: !Ref RedshiftClusterPort
          ToPort: !Ref RedshiftClusterPort
          CidrIp: 13.229.254.0/27
        - IpProtocol: tcp
          FromPort: !Ref RedshiftClusterPort
          ToPort: !Ref RedshiftClusterPort
          CidrIp: 54.153.249.96/27
        - IpProtocol: tcp
          FromPort: !Ref RedshiftClusterPort
          ToPort: !Ref RedshiftClusterPort
          CidrIp: 13.113.244.32/27
        - IpProtocol: tcp
          FromPort: !Ref RedshiftClusterPort
          ToPort: !Ref RedshiftClusterPort
          CidrIp: !Ref InboundTraffic
          
  sns:
    Type: 'AWS::SNS::Topic'
    Properties:
      Subscription:
        - Endpoint: !Ref SubscriptionEmail
          Protocol: Email
      TopicName: !Join [ "-", [!Ref 'AWS::StackName',"sns"] ]

  CFNMySpectrumRole:
    Type: AWS::IAM::Role
    Properties:
      RoleName: !Join [ "-", [!Ref 'AWS::StackName', "SpectrumRole"] ]
      AssumeRolePolicyDocument:
        Version: "2012-10-17"
        Statement:
          -
            Effect: "Allow"
            Principal:
              Service:
                - "redshift.amazonaws.com"
                - "glue.amazonaws.com"
            Action:
              - "sts:AssumeRole"
      Path: "/"
      Policies:
        -
          PolicyName: "spectrum-glue-required-access-policy"
          PolicyDocument:
            Version: "2012-10-17"
            Statement:
              -
                Effect: "Allow"
                Action:
                    - s3:GetBucketLocation
                    - s3:GetObject
                    - s3:ListMultipartUploadParts
                    - s3:ListBucket
                    - s3:ListBucketMultipartUploads
                Resource:
                    - !Join ['', ["arn:aws:s3:::", !Ref S3BucketForSpectrum]]
                    - !Join ['', ["arn:aws:s3:::", !Ref S3BucketForSpectrum, "/*"]]
                    - "arn:aws:s3:::redshift-downloads"
                    - "arn:aws:s3:::redshift-downloads/TPC-DS/*"
                    - "arn:aws:s3:::jwyant-tpcds/optimized/30tb/*"
              -
                Effect: Allow
                Action:
                    - glue:CreateDatabase
                    - glue:DeleteDatabase
                    - glue:GetDatabase
                    - glue:GetDatabases
                    - glue:UpdateDatabase
                    - glue:CreateTable
                    - glue:DeleteTable
                    - glue:BatchDeleteTable
                    - glue:UpdateTable
                    - glue:GetTable
                    - glue:GetTables
                    - glue:BatchCreatePartition
                    - glue:CreatePartition
                    - glue:DeletePartition
                    - glue:BatchDeletePartition
                    - glue:UpdatePartition
                    - glue:GetPartition
                    - glue:GetPartitions
                    - glue:BatchGetPartition
                    - logs:*
                Resource:
                    - "*"

  BastionSecurityGroup:
    Type: AWS::EC2::SecurityGroup
    Properties:
      GroupDescription: Enables SSH Access to Bastion Hosts from Corporate IPs
      VpcId: !Ref VPC
      Tags:
        - Key: "Name"
          Value: "SG for Bastion Host"
      SecurityGroupIngress:
      - IpProtocol: tcp
        FromPort: '22'
        ToPort: '22'
      - IpProtocol: tcp
        FromPort: '22'
        ToPort: '22'
        CidrIp: !Ref InboundTraffic
        
  BastionHost:
    Type: "AWS::EC2::Instance"
    DependsOn: RedshiftCluster
    CreationPolicy:
      ResourceSignal:
        Count: 1
        Timeout: PT90M
    Properties:
      InstanceType: !Ref InstanceType
      ImageId: 
        Fn::FindInMap:          
          - AWSAMIRegionMap
          - !Ref 'AWS::Region'
          - !FindInMap 
            - LinuxAMINameMap
            - 'Amazon-Linux-HVM'
            - Code
      UserData:
        "Fn::Base64": 
          !Sub |
            #!/bin/bash -ex
            export PATH=$PATH:/usr/local/bin
            yum update -y
            yum update -y aws-cfn-bootstrap
            export REDSHIFT_ENDPOINT=${RedshiftCluster.Endpoint.Address}
            export REDSHIFT_USER=${MasterUsername}
            export REDSHIFT_PASS=${MasterUserPassword}
            export REDSHIFT_DBNAME=${DatabaseName}
            export REDSHIFT_PORT=${RedshiftClusterPort}
            export REDSHIFT_IAMROLE=${CFNMySpectrumRole.Arn}
            /home/ec2-user/load_tpcds.py create
            /home/ec2-user/load_tpcds.py load
            /opt/aws/bin/cfn-signal --exit-code 0 --resource BastionHost --region ${AWS::Region} --stack ${AWS::StackName}
      KeyName: !Ref KeyPairName
      Tags:
        - Key: "Name"
          Value: "Bastion Host"
      NetworkInterfaces:
      - GroupSet: 
        - !Ref BastionSecurityGroup
        AssociatePublicIpAddress: true
        DeviceIndex: 0
        SubnetId: !Ref VPCPublicSubnet1
                                 
  RedshiftClusterParameterGroup:
    Type: 'AWS::Redshift::ClusterParameterGroup'
    Properties:
      Description: Cluster parameter group
      ParameterGroupFamily: redshift-1.0
      Parameters:
        - ParameterName: enable_user_activity_logging
          ParameterValue: 'false'
        - ParameterName: require_ssl
          ParameterValue: 'true'
        - ParameterName: max_concurrency_scaling_clusters
          ParameterValue: !Ref MaxConcurrentCluster
        - ParameterName: "wlm_json_configuration"
          ParameterValue: "[{\"user_group\":[\"etl_group\"],\"query_concurrency\":5,\"max_execution_time\":1800000,\"memory_percent_to_use\":70},{\"user_group\":[\"*ro*\"],\"user_group_wild_card\":1,\"query_concurrency\":2,\"concurrency_scaling\":\"auto\",\"max_execution_time\":120000,\"memory_percent_to_use\":15},{\"query_concurrency\":3,\"concurrency_scaling\":\"auto\",\"memory_percent_to_use\":5}]"
      Tags:
        -
          Key: Name
          Value: !Join [ "-", [ !Ref TagName, "Primary Cluster Parameter group" ] ]
        -
          Key: Environment
          Value: !Ref TagEnvironment
                      
  RedshiftClusterSubnetGroup:
    Type: 'AWS::Redshift::ClusterSubnetGroup'
    Properties:
      Description: Cluster subnet group
      SubnetIds:
        - !Ref VPCPublicSubnet1
        - !Ref VPCPublicSubnet2
      Tags:
        -
          Key: Name
          Value: !Join [ "-", [ !Ref TagName, !Ref 'AWS::StackName', "Primary Redshift Cluster Subnet group" ] ]
        -
          Key: Environment
          Value: !Ref TagEnvironment

  RedshiftCluster:
    Type: 'AWS::Redshift::Cluster'
    DependsOn: CFNMySpectrumRole
    Properties:
      ClusterType: !Ref ClusterType
      NumberOfNodes: !If 
        - IsMultiNodeCluster
        - !Ref NumberOfNodes
        - !Ref 'AWS::NoValue'
      NodeType: !Ref NodeType
      DBName: !Ref DatabaseName
      KmsKeyId: !If 
        - IsEncryptionAtRest
        - !Ref kmskey
        - !Ref 'AWS::NoValue'
      Encrypted: !Ref EncryptionAtRest
      Port: !Ref RedshiftClusterPort
      MasterUsername: !Ref MasterUsername
      MasterUserPassword: !Ref MasterUserPassword
      ClusterParameterGroupName: !Ref RedshiftClusterParameterGroup
      SnapshotIdentifier: !If 
        - IsSnapshotSpecified
        - !Ref SnapshotIdentifier
        - !Ref 'AWS::NoValue'
      OwnerAccount: !If 
        - IsSnapshotAccountSpecified
        - !Ref SnapshotAccountNumber
        - !Ref 'AWS::NoValue'
      VpcSecurityGroupIds:
        - !Ref SecurityGroup
      PreferredMaintenanceWindow: !Ref Maintenancewindow
      PubliclyAccessible: 'true'
      ClusterSubnetGroupName: !Ref RedshiftClusterSubnetGroup
      IamRoles:
        - 'Fn::GetAtt':
            - CFNMySpectrumRole
            - Arn
      Tags:
        -
          Key: Name
          Value: !Join [ "-", [ !Ref TagName, !Ref 'AWS::StackName', "Redshift-Cluster" ] ]
        -
          Key: Environment
          Value: !Ref TagEnvironment
            
  DiskSpacealarmredshift:
    Type: 'AWS::CloudWatch::Alarm'
    DependsOn: RedshiftCluster
    Properties:
      MetricName: !Join 
        - ''
        - - !Ref RedshiftCluster
          - High-PercentageDiskSpaceUsed
      AlarmDescription: !Join 
        - ''
        - - DiskSpace Utilization > 85% for
          - !Ref RedshiftCluster
      Namespace: AWS/Redshift
      Statistic: Average
      Period: '300'
      EvaluationPeriods: '3'
      Threshold: '85'
      AlarmActions:
        - !Ref sns
      Dimensions:
        - Name: ClusterIdentifier
          Value: !Ref RedshiftCluster
      ComparisonOperator: GreaterThanThreshold
      Unit: Percent

  GlueCatalogDB:
    DependsOn: CFNMySpectrumRole
    Type: 'AWS::Glue::Database'
    Properties:
      CatalogId: !Ref AWS::AccountId
      DatabaseInput:
          Name: !Ref GlueCatalogDatabase
          Description: AWS Glue Catalog database for demo

  GlueCrawler:
    Type: AWS::Glue::Crawler
    Properties:
      Name: !Join [ "-", [!Ref 'AWS::StackName', !Ref CrawlerNameSuffix] ]
      Role: !GetAtt CFNMySpectrumRole.Arn
      Description: AWS Glue crawler to crawl flights data
      DatabaseName: !Ref GlueCatalogDatabase
      Targets:
        S3Targets:
          - Path: !Ref SpectrumTableLocation
      TablePrefix: !Ref GlueTablePrefix
      Schedule:
        ScheduleExpression: "cron(0/30 * * * ? *)"
      SchemaChangePolicy:
        UpdateBehavior: "UPDATE_IN_DATABASE"
        DeleteBehavior: "LOG"
      Configuration: "{\"Version\":1.0,\"CrawlerOutput\":{\"Partitions\":{\"AddOrUpdateBehavior\":\"InheritFromTable\"},\"Tables\":{\"AddOrUpdateBehavior\":\"MergeNewColumns\"}}}"
   
Outputs:

  VPCID:
    Description: Created VPC (VPC-ID)
    Value: !Ref VPC
    Export: 
        Name: !Sub "${AWS::StackName}-VPC"

  VPCPublicSubnetID1:
    Description: Created VPCPublicSubnet1 
    Value: !Ref VPCPublicSubnet1
    Export: 
        Name: !Sub "${AWS::StackName}-VPCPublicSubnet1"
    
  VPCPublicSubnetID2:
    Description: Created VPCPublicSubnet2
    Value: !Ref VPCPublicSubnet2
    Export:  
        Name: !Sub "${AWS::StackName}-VPCPublicSubnet2"
        
  ClusterEndpoint:
    Description: Redshift Cluster endpoint
    Value: !Sub "${RedshiftCluster.Endpoint.Address}:${RedshiftCluster.Endpoint.Port}"
          
  RedshiftClusterName:
    Description: Name of the Redshift Cluster
    Value: !Ref RedshiftCluster
    
  RedshiftParameterGroupName:
    Description: Name of the Redshift Parameter Group
    Value: !Ref RedshiftClusterParameterGroup
    
  RedshiftClusterSubnetGroupName:
    Description: Name of the Cluster Subnet Group
    Value: !Ref RedshiftClusterSubnetGroup
    
  RedshiftDatabaseName:
    Description: Name of the Redshift Database
    Value: !Ref DatabaseName
    
  RedshiftUsername:
    Value: !Ref MasterUsername
    
  RedshiftClusterIAMRole:
    Description: IAM Role assigned to Redshift cluster & Glue Catalog
    Value: !GetAtt CFNMySpectrumRole.Arn

  GlueCatalogDBName:
    Description: Name of the AWS Glue Catalog Database
    Value: !Ref GlueCatalogDB

  GlueCrawlerName:
    Description: Name of the AWS Glue Crawler
    Value: !Ref GlueCrawler
