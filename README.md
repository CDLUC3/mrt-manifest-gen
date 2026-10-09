# Merritt Manifest Generator

This microservice is part of the [Merritt Preservation System](https://github.com/CDLUC3/mrt-doc). 

## Purpose

Facilitate the generation of Merritt manifests using a cloud bucket or an inventory list.

## Use Cases
- [Use Case 1](use-case-1.md): Work with UC3 "Ingest Workspace S3 Buckets" (UC3 owns the bucket and processes content on behalf of a Merritt depositor)
- [Use Case 2](use-case-2.md): Work directly with Depositor buckets using S3 https calls (GET/LIST) to a depositor bucket.
- [Use Case 3](use-case-3.md): General purpose tool to generate manifests from an inventory listing
  - Eventually use this tool to build manifests from a DAMS system

## Assumptions

Individual ingest workspaces should be optimized for working with approx 100,000 files at a time.  If the number of files exceeds this number and introduces complexity, we should consider breaking up the project into multiple workspaces.

## What is the application?

- The application will be built as a docker image that can be deployed to AWS lambda.
- The application should also be testable using docker-compose.
- If successful, the application might become a solution that could be deployed by Merritt depositors.
- The application will be used to experiment with thenew Merritt manifest structure.

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

