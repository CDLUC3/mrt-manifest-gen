# Manifest Generator Use Case 3: Inventory File Solution

- [Merritt Manifest Generator](README.md)

## Diagram

```mermaid
graph LR
  accTitle: 'Manifest Generator Use Case 1: UC3-Owned Source Bucket'
  accDescr {
    TBD
  }

  subgraph DepositorAccount
    DAMS[DAMS System - Digital Files]
    InventoryFile[Inventory File]
  end

  subgraph UC3Account
    S3CacheBucket[S3 Cache Bucket - Checkm and CSV]
    ManifestGeneratorLambda([Manifest Generator Lambda])
  end

  subgraph UC3VPC
    Ingest([Ingest Service])
    UI([Merritt UI])
  end

  subgraph Desktop
    Checkm[/Merritt Batch Manifest Checkm/]
  end

  DAMS --> InventoryFile
  InventoryFile --> |Https| ManifestGeneratorLambda
  DAMS --> |Https| Ingest
  ManifestGeneratorLambda <--> |S3Api| S3CacheBucket
  S3CacheBucket --> |S3HttpsApi| Ingest
  ManifestGeneratorLambda --> |Download| Checkm
  Checkm --> |Upload| UI
  UI -.-> Ingest
```

## Testing in Docker Compose
- Share AWS credentials to docker-compose to convey S3 access rights for the S3CacheBucket
- Eventually the application will be modified to use a file system rather than the S3CacheBucket
