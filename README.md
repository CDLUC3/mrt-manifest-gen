# Merritt Manifest Generator

This microservice is part of the [Merritt Preservation System](https://github.com/CDLUC3/mrt-doc). 

## Purpose

Facilitate the generation of Merritt manifests using a cloud bucket or an inventory list.

## Use Cases
- Use Case 1: Work with UC3 "Ingest Workspace S3 Buckets" (UC3 owns the bucket and can make S3 api calls)
  - Replace the existing Ingest Workspace Manifest Generator ([s3-sinatra](https://github.com/CDLUC3/s3-sinatra)) with a general purpose application.
- Use Case 2: Work with Depositor buckets (UC3 has permission to make https calls (GET/LIST) to a depository bucket).  Permissions should be granted to UC3 DEV and UC3 PROD VPC's.
- Use Case 3: General purpose tool to generate manifests from an inventory listing
  - Eventually use this tool to build manifests from a DAMS system

## What is the application?

- The application will be build as a docker image that can be deployed to AWS lambda.
- The application should also be testable using docker-compose.
  - Use Case 1: share AWS credentials with Docker Compose in order to convey S3 access pemissions
  - Use Case 2: execute docker compose from a UC3 DEV Workspace in order to convey VPC-based access rights.
  - Use Case 3: inputs may be passed to the application by file or by inventory listing held inside an S3 bucket
- If successful, the application might be usable when run by the depositor.
- The application must be flexible enough to support depositors in the transition to a new Merritt manifest structure.

## Security

### Manfiest Generation Application Permissions
- The web interface for this application should be restricted since it grants access to S3 content.
  - A public load balancer is in place which forces Cognito authentication.
- Because the web interface generates manifests for use by the Merritt ingest service, the Merritt ingest service needs access to this interface.
  - In the UC3 environment, the web interface runs in the same network as the Merritt Ingest service so a private load balancer can be utilized.
  - If we ever run this application outside of the UC3 environment, we will need to incorporate a solution that authorizes the Merritt ingest service to access the interface.

### Bucket/Digital File access
- Use Case 1
  - The Merritt Ingest service VPC should have HTTPS GET permissions on the bucket
    - files will be retrieved with an `https://....s3.us-west-2.amazonaws.com` URL
  - The Manifest Generation application should have S3 List and Get permissions to the bucket.
  - When a generated manifest is larger that 1 MB
    - The application should have the ability to PUT files and generate presigned URLs for those files
- Use Case 2
  - The Merritt Ingest service VPC should have HTTPS GET permissions on the bucket
    - files will be retrieved with an `https://....s3.us-west-2.amazonaws.com` URL
  - The Manifest Generation application will not have S3 API permissions on the bucket
    - The Manifest Generation application should have HTTPS GET and LIST permissions on the bucket
- Use Case 3
  - The Manifest Generation application will only have access to an inventory file.
  - The Manifest Generation application will generate URLs to a DAMS or other service
    - These urls need to grant the Merritt ingest service access to the DAMS data.

## Cache

- When running the application as a lambda, working files should be cached to S3.
- When running the application in docker-compose, working files could be cached to either S3 or to a file system.
- The cache bucket will likely have separate ownership from the source bucket.
  - All ingest workspace projects should be designed to operate out of a single cache bukcet with different key namespaces for each project.
  - Most of the cache should be entirely re-createable from the source.
  - The cache bucket might also be the intended location of metadata files that will be merged into the manifest.

### Cache Pathnames

- /PROJECT_NAME/
  - cache
    - inventory.csv: cache of full inventory listing.  This will be used for navigation until it is re-generated.
  - manifests
    - PATH.checkm: generated checkm for a specific path for a project
  metadata
    - PATH.csv: manually constructed metadata entry to be merged into the generated manifest

## Design

### Inputs

#### Required Inputs

- Input Type
  - S3 compatible bucket name
  - S3 https URL (with list permissions)
  - Inventory file
  - Inventory URL
- Cache Type
  - S3 or Filesystem
- Cache Name
  - Bucket or Fielsystem    

#### Configuration inputs (ENV or yaml TBD)
- prefix_path - if not processing the entire inventory
- retrieval_url - url prefix to insert into file urls in a manifest
- manifest_url - url prefix to insert into manifest url

#### Optional Inputs
- AWS credential mount
  - corresponding profile name passed in via ENV
- Metadata File

### Application States
- Inventory not loaded
- Inventory loaded
- Inventory refreshed

### Data to display
- view totals
  - file counts, bytes
  - file counts, bytes by extension
- manifest of manifest stats
  - number of manifests
  - average object count
  - average object size
  - average files per object
- navigate to subfolders

