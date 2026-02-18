#!/bin/bash
set -euo pipefail

# api_scaffold.sh - Scaffold CRUD API endpoints for a resource
# Usage: api_scaffold.sh <resource_name> [--framework=express|fastapi|nestjs] [project_path]
# Exit codes: 0=created, 1=already exists, 2=error

usage() {
    cat <<'USAGE'
Usage: api_scaffold.sh <resource_name> [options] [project_path]

Options:
  --framework=FRAMEWORK    express, fastapi, or nestjs (auto-detected if omitted)

Examples:
  api_scaffold.sh user
  api_scaffold.sh product --framework=fastapi
  api_scaffold.sh order --framework=nestjs /path/to/project
USAGE
    exit 2
}

# --- Parse Arguments ---
RESOURCE=""
FRAMEWORK=""
PROJECT_PATH=""

for arg in "$@"; do
    case "$arg" in
        --framework=*) FRAMEWORK="${arg#--framework=}" ;;
        --help|-h)     usage ;;
        -*)            echo "ERROR: Unknown option: $arg" >&2; usage ;;
        *)
            if [[ -z "$RESOURCE" ]]; then
                RESOURCE="$arg"
            elif [[ -z "$PROJECT_PATH" ]]; then
                PROJECT_PATH="$arg"
            fi
            ;;
    esac
done

if [[ -z "$RESOURCE" ]]; then
    echo "ERROR: Resource name is required." >&2
    usage
fi

PROJECT_PATH="${PROJECT_PATH:-$(git rev-parse --show-toplevel 2>/dev/null || echo ".")}"
PROJECT_PATH="$(cd "$PROJECT_PATH" && pwd)"

# --- Naming conventions ---
# snake_case for Python, camelCase/PascalCase for JS/TS
RESOURCE_LOWER=$(echo "$RESOURCE" | tr '[:upper:]' '[:lower:]')
RESOURCE_SNAKE=$(echo "$RESOURCE_LOWER" | tr '-' '_')
RESOURCE_PASCAL=$(echo "$RESOURCE_SNAKE" | sed -r 's/(^|_)([a-z])/\U\2/g')
RESOURCE_CAMEL=$(echo "$RESOURCE_PASCAL" | sed 's/^\(.\)/\L\1/')
RESOURCE_PLURAL="${RESOURCE_SNAKE}s"
RESOURCE_PASCAL_PLURAL="${RESOURCE_PASCAL}s"
RESOURCE_CAMEL_PLURAL="${RESOURCE_CAMEL}s"

# --- Auto-detect Framework ---
if [[ -z "$FRAMEWORK" ]]; then
    if [[ -f "$PROJECT_PATH/package.json" ]]; then
        if grep -q '"@nestjs/core"' "$PROJECT_PATH/package.json" 2>/dev/null; then
            FRAMEWORK="nestjs"
        elif grep -q '"express"' "$PROJECT_PATH/package.json" 2>/dev/null; then
            FRAMEWORK="express"
        elif grep -q '"fastify"' "$PROJECT_PATH/package.json" 2>/dev/null; then
            FRAMEWORK="express"  # Similar structure
        fi
    fi
    if [[ -z "$FRAMEWORK" ]]; then
        for pyfile in "$PROJECT_PATH/pyproject.toml" "$PROJECT_PATH/requirements.txt" "$PROJECT_PATH/setup.py"; do
            if [[ -f "$pyfile" ]] && grep -qi "fastapi" "$pyfile" 2>/dev/null; then
                FRAMEWORK="fastapi"
                break
            fi
            if [[ -f "$pyfile" ]] && grep -qi "django" "$pyfile" 2>/dev/null; then
                FRAMEWORK="fastapi"  # Use FastAPI-style as closest
                echo "NOTE: Django detected but scaffolding FastAPI-style. Adjust as needed." >&2
                break
            fi
        done
    fi
fi

if [[ -z "$FRAMEWORK" ]]; then
    echo "ERROR: Cannot auto-detect framework. Use --framework=express|fastapi|nestjs" >&2
    exit 2
fi

echo "========================================"
echo " API Scaffold: $RESOURCE_PASCAL"
echo " Framework: $FRAMEWORK"
echo "========================================"
echo ""

# ============================================================
# Express
# ============================================================

scaffold_express() {
    local SRC_DIR="$PROJECT_PATH/src"
    if [[ ! -d "$SRC_DIR" ]]; then
        SRC_DIR="$PROJECT_PATH"
    fi

    local ROUTE_DIR="$SRC_DIR/routes"
    local ROUTE_FILE="$ROUTE_DIR/${RESOURCE_CAMEL_PLURAL}.ts"

    # Check for JS vs TS
    local EXT="ts"
    if [[ ! -f "$PROJECT_PATH/tsconfig.json" ]]; then
        EXT="js"
        ROUTE_FILE="$ROUTE_DIR/${RESOURCE_CAMEL_PLURAL}.js"
    fi

    if [[ -f "$ROUTE_FILE" ]]; then
        echo "ERROR: Route file already exists: $ROUTE_FILE" >&2
        exit 1
    fi

    mkdir -p "$ROUTE_DIR"

    if [[ "$EXT" == "ts" ]]; then
        cat > "$ROUTE_FILE" <<EXPRESSROUTE
import { Router, Request, Response, NextFunction } from 'express';

const router = Router();

// --- Types ---
interface ${RESOURCE_PASCAL} {
  id: string;
  // TODO: Add fields
  createdAt: Date;
  updatedAt: Date;
}

interface Create${RESOURCE_PASCAL}Body {
  // TODO: Add validation
}

interface Update${RESOURCE_PASCAL}Body {
  // TODO: Add validation
}

// --- Validation Middleware ---
function validateCreate(req: Request, res: Response, next: NextFunction): void {
  const body = req.body as Create${RESOURCE_PASCAL}Body;
  // TODO: Add validation logic (consider using zod, joi, or express-validator)
  // if (!body.name) {
  //   res.status(400).json({ error: 'name is required' });
  //   return;
  // }
  next();
}

function validateUpdate(req: Request, res: Response, next: NextFunction): void {
  const body = req.body as Update${RESOURCE_PASCAL}Body;
  // TODO: Add validation logic
  next();
}

// --- Handlers ---

// GET /${RESOURCE_PLURAL} - List all
router.get('/', async (req: Request, res: Response) => {
  try {
    // TODO: Implement list logic
    // const ${RESOURCE_CAMEL_PLURAL} = await ${RESOURCE_PASCAL}.findAll();
    res.json({ data: [], total: 0 });
  } catch (error) {
    res.status(500).json({ error: 'Failed to fetch ${RESOURCE_PLURAL}' });
  }
});

// GET /${RESOURCE_PLURAL}/:id - Get one
router.get('/:id', async (req: Request, res: Response) => {
  try {
    const { id } = req.params;
    // TODO: Implement get logic
    // const ${RESOURCE_CAMEL} = await ${RESOURCE_PASCAL}.findById(id);
    // if (!${RESOURCE_CAMEL}) {
    //   return res.status(404).json({ error: '${RESOURCE_PASCAL} not found' });
    // }
    res.json({ data: { id } });
  } catch (error) {
    res.status(500).json({ error: 'Failed to fetch ${RESOURCE_SNAKE}' });
  }
});

// POST /${RESOURCE_PLURAL} - Create
router.post('/', validateCreate, async (req: Request, res: Response) => {
  try {
    const body = req.body as Create${RESOURCE_PASCAL}Body;
    // TODO: Implement create logic
    // const ${RESOURCE_CAMEL} = await ${RESOURCE_PASCAL}.create(body);
    res.status(201).json({ data: body });
  } catch (error) {
    res.status(500).json({ error: 'Failed to create ${RESOURCE_SNAKE}' });
  }
});

// PUT /${RESOURCE_PLURAL}/:id - Update
router.put('/:id', validateUpdate, async (req: Request, res: Response) => {
  try {
    const { id } = req.params;
    const body = req.body as Update${RESOURCE_PASCAL}Body;
    // TODO: Implement update logic
    // const ${RESOURCE_CAMEL} = await ${RESOURCE_PASCAL}.findByIdAndUpdate(id, body);
    res.json({ data: { id, ...body } });
  } catch (error) {
    res.status(500).json({ error: 'Failed to update ${RESOURCE_SNAKE}' });
  }
});

// DELETE /${RESOURCE_PLURAL}/:id - Delete
router.delete('/:id', async (req: Request, res: Response) => {
  try {
    const { id } = req.params;
    // TODO: Implement delete logic
    // await ${RESOURCE_PASCAL}.findByIdAndDelete(id);
    res.status(204).send();
  } catch (error) {
    res.status(500).json({ error: 'Failed to delete ${RESOURCE_SNAKE}' });
  }
});

export default router;

// Register in your app:
// import ${RESOURCE_CAMEL_PLURAL}Router from './routes/${RESOURCE_CAMEL_PLURAL}';
// app.use('/api/${RESOURCE_PLURAL}', ${RESOURCE_CAMEL_PLURAL}Router);
EXPRESSROUTE
    else
        cat > "$ROUTE_FILE" <<EXPRESSJS
const { Router } = require('express');

const router = Router();

// --- Validation Middleware ---
function validateCreate(req, res, next) {
  // TODO: Add validation logic
  next();
}

function validateUpdate(req, res, next) {
  // TODO: Add validation logic
  next();
}

// GET /${RESOURCE_PLURAL}
router.get('/', async (req, res) => {
  try {
    res.json({ data: [], total: 0 });
  } catch (error) {
    res.status(500).json({ error: 'Failed to fetch ${RESOURCE_PLURAL}' });
  }
});

// GET /${RESOURCE_PLURAL}/:id
router.get('/:id', async (req, res) => {
  try {
    const { id } = req.params;
    res.json({ data: { id } });
  } catch (error) {
    res.status(500).json({ error: 'Failed to fetch ${RESOURCE_SNAKE}' });
  }
});

// POST /${RESOURCE_PLURAL}
router.post('/', validateCreate, async (req, res) => {
  try {
    res.status(201).json({ data: req.body });
  } catch (error) {
    res.status(500).json({ error: 'Failed to create ${RESOURCE_SNAKE}' });
  }
});

// PUT /${RESOURCE_PLURAL}/:id
router.put('/:id', validateUpdate, async (req, res) => {
  try {
    const { id } = req.params;
    res.json({ data: { id, ...req.body } });
  } catch (error) {
    res.status(500).json({ error: 'Failed to update ${RESOURCE_SNAKE}' });
  }
});

// DELETE /${RESOURCE_PLURAL}/:id
router.delete('/:id', async (req, res) => {
  try {
    const { id } = req.params;
    res.status(204).send();
  } catch (error) {
    res.status(500).json({ error: 'Failed to delete ${RESOURCE_SNAKE}' });
  }
});

module.exports = router;

// Register in your app:
// const ${RESOURCE_CAMEL_PLURAL}Router = require('./routes/${RESOURCE_CAMEL_PLURAL}');
// app.use('/api/${RESOURCE_PLURAL}', ${RESOURCE_CAMEL_PLURAL}Router);
EXPRESSJS
    fi

    echo "  Files created:"
    echo "    $ROUTE_FILE"
    echo ""
    echo "  Register the route in your app:"
    echo "    app.use('/api/${RESOURCE_PLURAL}', ${RESOURCE_CAMEL_PLURAL}Router);"
}

# ============================================================
# FastAPI
# ============================================================

scaffold_fastapi() {
    local APP_DIR="$PROJECT_PATH/app"
    if [[ ! -d "$APP_DIR" ]]; then
        APP_DIR="$PROJECT_PATH/src"
        if [[ ! -d "$APP_DIR" ]]; then
            APP_DIR="$PROJECT_PATH"
        fi
    fi

    local ROUTER_DIR="$APP_DIR/routers"
    local ROUTER_FILE="$ROUTER_DIR/${RESOURCE_SNAKE}.py"
    local SCHEMA_DIR="$APP_DIR/schemas"
    local SCHEMA_FILE="$SCHEMA_DIR/${RESOURCE_SNAKE}.py"

    if [[ -f "$ROUTER_FILE" ]]; then
        echo "ERROR: Router file already exists: $ROUTER_FILE" >&2
        exit 1
    fi

    mkdir -p "$ROUTER_DIR" "$SCHEMA_DIR"

    # Touch __init__.py files
    [[ ! -f "$ROUTER_DIR/__init__.py" ]] && touch "$ROUTER_DIR/__init__.py"
    [[ ! -f "$SCHEMA_DIR/__init__.py" ]] && touch "$SCHEMA_DIR/__init__.py"

    # Pydantic schemas
    cat > "$SCHEMA_FILE" <<PYSCHEMA
from datetime import datetime
from pydantic import BaseModel, Field


class ${RESOURCE_PASCAL}Base(BaseModel):
    """Shared fields for ${RESOURCE_PASCAL}."""
    # TODO: Add fields
    # name: str = Field(..., min_length=1, max_length=255)
    pass


class ${RESOURCE_PASCAL}Create(${RESOURCE_PASCAL}Base):
    """Fields required to create a ${RESOURCE_PASCAL}."""
    pass


class ${RESOURCE_PASCAL}Update(BaseModel):
    """Fields that can be updated on a ${RESOURCE_PASCAL}. All optional."""
    # TODO: Add optional fields
    # name: str | None = None
    pass


class ${RESOURCE_PASCAL}Response(${RESOURCE_PASCAL}Base):
    """Response schema for ${RESOURCE_PASCAL}."""
    id: str
    created_at: datetime
    updated_at: datetime

    model_config = {"from_attributes": True}


class ${RESOURCE_PASCAL}ListResponse(BaseModel):
    """Paginated list response."""
    data: list[${RESOURCE_PASCAL}Response]
    total: int
    page: int
    page_size: int
PYSCHEMA

    # Router
    cat > "$ROUTER_FILE" <<PYROUTER
from fastapi import APIRouter, HTTPException, Query, Path
from typing import Annotated

from schemas.${RESOURCE_SNAKE} import (
    ${RESOURCE_PASCAL}Create,
    ${RESOURCE_PASCAL}Update,
    ${RESOURCE_PASCAL}Response,
    ${RESOURCE_PASCAL}ListResponse,
)

router = APIRouter(
    prefix="/${RESOURCE_PLURAL}",
    tags=["${RESOURCE_PASCAL_PLURAL}"],
)


@router.get("/", response_model=${RESOURCE_PASCAL}ListResponse)
async def list_${RESOURCE_PLURAL}(
    page: Annotated[int, Query(ge=1)] = 1,
    page_size: Annotated[int, Query(ge=1, le=100)] = 20,
):
    """List all ${RESOURCE_PLURAL} with pagination."""
    # TODO: Implement list logic
    # ${RESOURCE_PLURAL} = await ${RESOURCE_SNAKE}_repo.find_many(skip=(page-1)*page_size, limit=page_size)
    return ${RESOURCE_PASCAL}ListResponse(data=[], total=0, page=page, page_size=page_size)


@router.get("/{${RESOURCE_SNAKE}_id}", response_model=${RESOURCE_PASCAL}Response)
async def get_${RESOURCE_SNAKE}(
    ${RESOURCE_SNAKE}_id: Annotated[str, Path(description="${RESOURCE_PASCAL} ID")],
):
    """Get a single ${RESOURCE_SNAKE} by ID."""
    # TODO: Implement get logic
    # ${RESOURCE_SNAKE} = await ${RESOURCE_SNAKE}_repo.find_by_id(${RESOURCE_SNAKE}_id)
    # if not ${RESOURCE_SNAKE}:
    #     raise HTTPException(status_code=404, detail="${RESOURCE_PASCAL} not found")
    raise HTTPException(status_code=501, detail="Not implemented")


@router.post("/", response_model=${RESOURCE_PASCAL}Response, status_code=201)
async def create_${RESOURCE_SNAKE}(
    body: ${RESOURCE_PASCAL}Create,
):
    """Create a new ${RESOURCE_SNAKE}."""
    # TODO: Implement create logic
    # ${RESOURCE_SNAKE} = await ${RESOURCE_SNAKE}_repo.create(body.model_dump())
    raise HTTPException(status_code=501, detail="Not implemented")


@router.put("/{${RESOURCE_SNAKE}_id}", response_model=${RESOURCE_PASCAL}Response)
async def update_${RESOURCE_SNAKE}(
    ${RESOURCE_SNAKE}_id: Annotated[str, Path(description="${RESOURCE_PASCAL} ID")],
    body: ${RESOURCE_PASCAL}Update,
):
    """Update an existing ${RESOURCE_SNAKE}."""
    # TODO: Implement update logic
    # ${RESOURCE_SNAKE} = await ${RESOURCE_SNAKE}_repo.update(${RESOURCE_SNAKE}_id, body.model_dump(exclude_unset=True))
    # if not ${RESOURCE_SNAKE}:
    #     raise HTTPException(status_code=404, detail="${RESOURCE_PASCAL} not found")
    raise HTTPException(status_code=501, detail="Not implemented")


@router.delete("/{${RESOURCE_SNAKE}_id}", status_code=204)
async def delete_${RESOURCE_SNAKE}(
    ${RESOURCE_SNAKE}_id: Annotated[str, Path(description="${RESOURCE_PASCAL} ID")],
):
    """Delete a ${RESOURCE_SNAKE}."""
    # TODO: Implement delete logic
    # deleted = await ${RESOURCE_SNAKE}_repo.delete(${RESOURCE_SNAKE}_id)
    # if not deleted:
    #     raise HTTPException(status_code=404, detail="${RESOURCE_PASCAL} not found")
    raise HTTPException(status_code=501, detail="Not implemented")


# Register in your app:
# from routers.${RESOURCE_SNAKE} import router as ${RESOURCE_SNAKE}_router
# app.include_router(${RESOURCE_SNAKE}_router, prefix="/api")
PYROUTER

    echo "  Files created:"
    echo "    $ROUTER_FILE"
    echo "    $SCHEMA_FILE"
    echo ""
    echo "  Register the router in your app:"
    echo "    app.include_router(${RESOURCE_SNAKE}_router, prefix=\"/api\")"
}

# ============================================================
# NestJS
# ============================================================

scaffold_nestjs() {
    local SRC_DIR="$PROJECT_PATH/src"
    if [[ ! -d "$SRC_DIR" ]]; then
        SRC_DIR="$PROJECT_PATH"
    fi

    local MOD_DIR="$SRC_DIR/${RESOURCE_SNAKE}"

    if [[ -d "$MOD_DIR" ]]; then
        echo "ERROR: Module directory already exists: $MOD_DIR" >&2
        exit 1
    fi

    mkdir -p "$MOD_DIR/dto"

    # DTO: Create
    cat > "$MOD_DIR/dto/create-${RESOURCE_LOWER}.dto.ts" <<CREATEDTO
import { IsString, IsNotEmpty, IsOptional } from 'class-validator';

export class Create${RESOURCE_PASCAL}Dto {
  // TODO: Add fields with validation decorators

  // @IsString()
  // @IsNotEmpty()
  // name: string;

  // @IsString()
  // @IsOptional()
  // description?: string;
}
CREATEDTO

    # DTO: Update
    cat > "$MOD_DIR/dto/update-${RESOURCE_LOWER}.dto.ts" <<UPDATEDTO
import { PartialType } from '@nestjs/mapped-types';
import { Create${RESOURCE_PASCAL}Dto } from './create-${RESOURCE_LOWER}.dto';

export class Update${RESOURCE_PASCAL}Dto extends PartialType(Create${RESOURCE_PASCAL}Dto) {}
UPDATEDTO

    # DTO: barrel
    cat > "$MOD_DIR/dto/index.ts" <<DTOINDEX
export { Create${RESOURCE_PASCAL}Dto } from './create-${RESOURCE_LOWER}.dto';
export { Update${RESOURCE_PASCAL}Dto } from './update-${RESOURCE_LOWER}.dto';
DTOINDEX

    # Service
    cat > "$MOD_DIR/${RESOURCE_SNAKE}.service.ts" <<SERVICE
import { Injectable, NotFoundException } from '@nestjs/common';
import { Create${RESOURCE_PASCAL}Dto, Update${RESOURCE_PASCAL}Dto } from './dto';

@Injectable()
export class ${RESOURCE_PASCAL}Service {
  // TODO: Inject repository
  // constructor(
  //   @InjectRepository(${RESOURCE_PASCAL})
  //   private readonly ${RESOURCE_CAMEL}Repository: Repository<${RESOURCE_PASCAL}>,
  // ) {}

  async findAll() {
    // TODO: Implement
    return [];
  }

  async findOne(id: string) {
    // TODO: Implement
    // const ${RESOURCE_CAMEL} = await this.${RESOURCE_CAMEL}Repository.findOne({ where: { id } });
    // if (!${RESOURCE_CAMEL}) {
    //   throw new NotFoundException('${RESOURCE_PASCAL} not found');
    // }
    // return ${RESOURCE_CAMEL};
    throw new NotFoundException('${RESOURCE_PASCAL} not found');
  }

  async create(dto: Create${RESOURCE_PASCAL}Dto) {
    // TODO: Implement
    // const ${RESOURCE_CAMEL} = this.${RESOURCE_CAMEL}Repository.create(dto);
    // return this.${RESOURCE_CAMEL}Repository.save(${RESOURCE_CAMEL});
    return dto;
  }

  async update(id: string, dto: Update${RESOURCE_PASCAL}Dto) {
    // TODO: Implement
    // const ${RESOURCE_CAMEL} = await this.findOne(id);
    // Object.assign(${RESOURCE_CAMEL}, dto);
    // return this.${RESOURCE_CAMEL}Repository.save(${RESOURCE_CAMEL});
    return { id, ...dto };
  }

  async remove(id: string) {
    // TODO: Implement
    // const ${RESOURCE_CAMEL} = await this.findOne(id);
    // return this.${RESOURCE_CAMEL}Repository.remove(${RESOURCE_CAMEL});
  }
}
SERVICE

    # Controller
    cat > "$MOD_DIR/${RESOURCE_SNAKE}.controller.ts" <<CONTROLLER
import {
  Controller,
  Get,
  Post,
  Put,
  Delete,
  Body,
  Param,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';
import { ${RESOURCE_PASCAL}Service } from './${RESOURCE_SNAKE}.service';
import { Create${RESOURCE_PASCAL}Dto, Update${RESOURCE_PASCAL}Dto } from './dto';

@Controller('${RESOURCE_PLURAL}')
export class ${RESOURCE_PASCAL}Controller {
  constructor(private readonly ${RESOURCE_CAMEL}Service: ${RESOURCE_PASCAL}Service) {}

  @Get()
  findAll() {
    return this.${RESOURCE_CAMEL}Service.findAll();
  }

  @Get(':id')
  findOne(@Param('id') id: string) {
    return this.${RESOURCE_CAMEL}Service.findOne(id);
  }

  @Post()
  @HttpCode(HttpStatus.CREATED)
  create(@Body() dto: Create${RESOURCE_PASCAL}Dto) {
    return this.${RESOURCE_CAMEL}Service.create(dto);
  }

  @Put(':id')
  update(@Param('id') id: string, @Body() dto: Update${RESOURCE_PASCAL}Dto) {
    return this.${RESOURCE_CAMEL}Service.update(id, dto);
  }

  @Delete(':id')
  @HttpCode(HttpStatus.NO_CONTENT)
  remove(@Param('id') id: string) {
    return this.${RESOURCE_CAMEL}Service.remove(id);
  }
}
CONTROLLER

    # Module
    cat > "$MOD_DIR/${RESOURCE_SNAKE}.module.ts" <<MODULE
import { Module } from '@nestjs/common';
import { ${RESOURCE_PASCAL}Controller } from './${RESOURCE_SNAKE}.controller';
import { ${RESOURCE_PASCAL}Service } from './${RESOURCE_SNAKE}.service';

@Module({
  controllers: [${RESOURCE_PASCAL}Controller],
  providers: [${RESOURCE_PASCAL}Service],
  exports: [${RESOURCE_PASCAL}Service],
})
export class ${RESOURCE_PASCAL}Module {}

// Register in AppModule:
// import { ${RESOURCE_PASCAL}Module } from './${RESOURCE_SNAKE}/${RESOURCE_SNAKE}.module';
// @Module({ imports: [..., ${RESOURCE_PASCAL}Module] })
MODULE

    echo "  Files created:"
    for f in "$MOD_DIR"/*.ts "$MOD_DIR"/dto/*.ts; do
        echo "    ${f#$PROJECT_PATH/}"
    done
    echo ""
    echo "  Register the module in AppModule:"
    echo "    imports: [..., ${RESOURCE_PASCAL}Module]"
}

# --- Dispatch ---
case "$FRAMEWORK" in
    express)  scaffold_express ;;
    fastapi)  scaffold_fastapi ;;
    nestjs)   scaffold_nestjs ;;
    *)
        echo "ERROR: Unsupported framework: $FRAMEWORK" >&2
        echo "Supported: express, fastapi, nestjs" >&2
        exit 2
        ;;
esac

echo ""
echo "  Scaffold complete!"
exit 0
