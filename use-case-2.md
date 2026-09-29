# Manifest Generator Use Case 2: Depositor-Owned Source Bucket

- [Merritt Manifest Generator](README.md)

## Diagram

```mermaid
graph LR
  accTitle: 'Manifest Generator Use Case 1: UC3-Owned Source Bucket'
  accDescr {
    TBD
  }

  subgraph DepositorAccount
    S3SourceBucket[S3 Source Bucket - Digital Files]
  end

  subgraph UC3Account
    S3CacheBucket[S3 Cache Bucket - Checkm and CSV]
  end

  subgraph UC3VPC
    ManifestGeneratorLambda([Manifest Generator Lambda])
    UI([Merritt UI])
    Ingest([Ingest Service])
  end

  subgraph Desktop
    Checkm[/Merritt Batch Manifest Checkm/]
  end

  S3SourceBucket --> |S3HttpsApi| ManifestGeneratorLambda
  S3SourceBucket --> |S3HttpsApi| Ingest
  ManifestGeneratorLambda <--> |S3Api| S3CacheBucket
  S3CacheBucket --> |S3HttpsApi| Ingest
  ManifestGeneratorLambda --> |Download| Checkm
  Checkm --> |Upload| UI
  UI -.-> Ingest
```

## Configuration Needs
- ManifestGeneratorLambda needs s3https read/list access to S3SourceBucket
- ManifestGeneratorLambda needs S3 read/write access to S3CacheBucket
- Ingest needs s3https read access to S3SourceBucket
- Ingest needs s3https read access to S3CacheBucket

## Testing in Docker Compose
- Share AWS credentials to docker-compose to convey S3 access rights for the S3CacheBucket
- Run docker compose from an DEV Workspace in order to enable S3httpsapi access

```bash
PROJECT_NAME=xxx docker compose -f docker-compose.yml -f use-case-2.yml up -d --build
```