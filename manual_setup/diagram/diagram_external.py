from diagrams import Cluster, Diagram, Edge
from diagrams.aws.compute import EC2
from diagrams.aws.network import VPC, PrivateSubnet, PublicSubnet, InternetGateway, NATGateway, ElbApplicationLoadBalancer
from diagrams.onprem.compute import Server
from diagrams.aws.storage import SimpleStorageServiceS3Bucket
from diagrams.aws.database import RDSPostgresqlInstance

# Variables
title = "VPC with 1 public subnet for the TFE server and\n 2 private subnet in different AZ for the PostgreSQL instance requirement."
outformat = "png"
filename = "diagram-external"
direction = "TB"


with Diagram(
    name=title,
    direction=direction,
    filename=filename,
    outformat=outformat,
) as diag:
    # Non Clustered
    user = Server("user")

    # Cluster 
    with Cluster("aws"):
        bucket = SimpleStorageServiceS3Bucket("TFE bucket")
        with Cluster("vpc"):
            igw_gateway = InternetGateway("igw")
    
            with Cluster("Availability Zone: eu-north-1b"):        
                # Subcluster
                with Cluster("subnet_private2"):
                    postgresql2 = RDSPostgresqlInstance("RDS different AZ")
            with Cluster("Availability Zone: eu-north-1a"):
                # Subcluster 
                with Cluster("subnet_public1"):
                     ec2_tfe_server = EC2("TFE_server")
                # Subcluster
                with Cluster("subnet_private1"):
                    postgresql = RDSPostgresqlInstance("RDS Instance")
    # Diagram
    user >> ec2_tfe_server 

    bucket

    ec2_tfe_server >> [postgresql,
                       bucket]

diag
