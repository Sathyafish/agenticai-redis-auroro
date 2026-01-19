# Images Directory

This directory contains images used in the project documentation.

## Current Images

### architecture-diagram.png
**Required:** Save your architecture diagram here as `architecture-diagram.png`

The diagram should illustrate:
- AWS VPC with public and private subnets
- Load Balancer in public subnet
- ECS Cluster with Planner and Worker containers
- Aurora PostgreSQL (with pgvector)
- ElastiCache Redis
- AWS Secrets Manager
- CloudWatch Logs
- ECR repositories
- Data flow between components

**Recommended specifications:**
- Format: PNG (transparent background preferred)
- Resolution: 1920x1080 or similar widescreen aspect ratio
- Background: Dark theme preferred (to match documentation style)
- File size: < 500KB

## Adding New Images

When adding new images:
1. Use descriptive filenames (kebab-case: `my-feature-diagram.png`)
2. Optimize images before committing (use tools like TinyPNG)
3. Update this README with image descriptions
4. Reference images in documentation using relative paths: `assets/images/filename.png`
