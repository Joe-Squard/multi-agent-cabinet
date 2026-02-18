#!/bin/bash
# project_init.sh - プロジェクト初期化テンプレート生成
# 使い方: ./tools/architect/project_init.sh --stack=nextjs --db=postgres [--name=myapp]
set -euo pipefail

STACK=""
DB=""
PROJECT_NAME="my-app"
OUTPUT_DIR=""

# 引数解析
for arg in "$@"; do
    case "$arg" in
        --stack=*) STACK="${arg#*=}" ;;
        --db=*) DB="${arg#*=}" ;;
        --name=*) PROJECT_NAME="${arg#*=}" ;;
        --output=*) OUTPUT_DIR="${arg#*=}" ;;
        --help|-h)
            echo "使い方: $0 --stack=<stack> [--db=<db>] [--name=<name>] [--output=<dir>]"
            echo ""
            echo "スタック:"
            echo "  nextjs     Next.js (App Router, TypeScript)"
            echo "  react      React + Vite (TypeScript)"
            echo "  express    Express.js (TypeScript)"
            echo "  fastapi    FastAPI (Python)"
            echo "  nestjs     NestJS (TypeScript)"
            echo "  rn         React Native (Expo, TypeScript)"
            echo "  fullstack  Next.js + API Routes + DB"
            echo ""
            echo "DB:"
            echo "  postgres   PostgreSQL (+ Prisma)"
            echo "  mysql      MySQL (+ Prisma)"
            echo "  sqlite     SQLite (+ Prisma)"
            echo "  mongo      MongoDB (+ Mongoose)"
            echo "  supabase   Supabase (PostgreSQL)"
            echo "  none       DB なし"
            exit 0
            ;;
    esac
done

if [ -z "$STACK" ]; then
    echo "ERROR: --stack は必須です" >&2
    echo "$0 --help で使い方を確認してください" >&2
    exit 2
fi

echo "=============================================="
echo " プロジェクト初期化テンプレート"
echo " 名前: $PROJECT_NAME"
echo " スタック: $STACK"
echo " DB: ${DB:-none}"
echo "=============================================="
echo ""

# ディレクトリ構造生成
echo "## 推奨ディレクトリ構造"
echo ""
echo '```'
case "$STACK" in
    nextjs|fullstack)
        cat <<TREE
${PROJECT_NAME}/
├── src/
│   ├── app/
│   │   ├── layout.tsx
│   │   ├── page.tsx
│   │   ├── globals.css
│   │   ├── (auth)/
│   │   │   ├── login/page.tsx
│   │   │   └── register/page.tsx
│   │   ├── dashboard/
│   │   │   └── page.tsx
│   │   └── api/
│   │       └── [...route]/route.ts
│   ├── components/
│   │   ├── ui/           # 汎用UIコンポーネント
│   │   ├── forms/        # フォーム関連
│   │   └── layouts/      # レイアウト
│   ├── lib/
│   │   ├── db.ts         # DB接続
│   │   ├── auth.ts       # 認証ヘルパー
│   │   └── utils.ts      # ユーティリティ
│   ├── hooks/            # カスタムフック
│   ├── types/            # 型定義
│   └── styles/           # スタイル
├── prisma/
│   └── schema.prisma
├── public/
├── tests/
├── .env.example
├── .env.local
├── .gitignore
├── next.config.ts
├── tailwind.config.ts
├── tsconfig.json
├── package.json
└── README.md
TREE
        ;;
    react)
        cat <<TREE
${PROJECT_NAME}/
├── src/
│   ├── main.tsx
│   ├── App.tsx
│   ├── components/
│   │   ├── ui/
│   │   └── features/
│   ├── pages/
│   ├── hooks/
│   ├── lib/
│   ├── types/
│   ├── styles/
│   └── assets/
├── public/
├── tests/
├── .env.example
├── .gitignore
├── vite.config.ts
├── tailwind.config.ts
├── tsconfig.json
├── package.json
└── README.md
TREE
        ;;
    express)
        cat <<TREE
${PROJECT_NAME}/
├── src/
│   ├── index.ts
│   ├── app.ts
│   ├── routes/
│   │   ├── index.ts
│   │   ├── auth.routes.ts
│   │   └── users.routes.ts
│   ├── controllers/
│   ├── services/
│   ├── middleware/
│   │   ├── auth.ts
│   │   ├── errorHandler.ts
│   │   └── validation.ts
│   ├── models/
│   ├── types/
│   ├── utils/
│   └── config/
├── prisma/
│   └── schema.prisma
├── tests/
├── .env.example
├── .gitignore
├── tsconfig.json
├── package.json
└── README.md
TREE
        ;;
    fastapi)
        cat <<TREE
${PROJECT_NAME}/
├── app/
│   ├── __init__.py
│   ├── main.py
│   ├── config.py
│   ├── routers/
│   │   ├── __init__.py
│   │   ├── auth.py
│   │   └── users.py
│   ├── models/
│   │   ├── __init__.py
│   │   └── user.py
│   ├── schemas/
│   │   ├── __init__.py
│   │   └── user.py
│   ├── services/
│   ├── middleware/
│   └── utils/
├── alembic/
│   └── versions/
├── tests/
├── .env.example
├── .gitignore
├── alembic.ini
├── pyproject.toml
├── requirements.txt
└── README.md
TREE
        ;;
    nestjs)
        cat <<TREE
${PROJECT_NAME}/
├── src/
│   ├── main.ts
│   ├── app.module.ts
│   ├── app.controller.ts
│   ├── app.service.ts
│   ├── auth/
│   │   ├── auth.module.ts
│   │   ├── auth.controller.ts
│   │   ├── auth.service.ts
│   │   └── dto/
│   ├── users/
│   │   ├── users.module.ts
│   │   ├── users.controller.ts
│   │   ├── users.service.ts
│   │   ├── entities/
│   │   └── dto/
│   ├── common/
│   │   ├── decorators/
│   │   ├── filters/
│   │   ├── guards/
│   │   └── interceptors/
│   └── config/
├── prisma/
│   └── schema.prisma
├── test/
├── .env.example
├── .gitignore
├── nest-cli.json
├── tsconfig.json
├── package.json
└── README.md
TREE
        ;;
    rn)
        cat <<TREE
${PROJECT_NAME}/
├── app/
│   ├── _layout.tsx
│   ├── index.tsx
│   ├── (tabs)/
│   │   ├── _layout.tsx
│   │   ├── home.tsx
│   │   ├── profile.tsx
│   │   └── settings.tsx
│   └── (auth)/
│       ├── login.tsx
│       └── register.tsx
├── components/
│   ├── ui/
│   └── features/
├── hooks/
├── lib/
├── types/
├── constants/
├── assets/
│   ├── images/
│   └── fonts/
├── .env.example
├── .gitignore
├── app.json
├── tsconfig.json
├── package.json
└── README.md
TREE
        ;;
    *)
        echo "ERROR: 不明なスタック: $STACK" >&2
        exit 2
        ;;
esac
echo '```'
echo ""

# 初期化コマンド
echo "## 初期化コマンド"
echo ""
echo '```bash'
case "$STACK" in
    nextjs|fullstack)
        echo "npx create-next-app@latest $PROJECT_NAME --typescript --tailwind --eslint --app --src-dir --import-alias \"@/*\""
        [ -n "$DB" ] && [ "$DB" != "none" ] && echo "cd $PROJECT_NAME && npm install prisma @prisma/client && npx prisma init"
        ;;
    react)
        echo "npm create vite@latest $PROJECT_NAME -- --template react-ts"
        echo "cd $PROJECT_NAME && npm install && npm install -D tailwindcss postcss autoprefixer"
        ;;
    express)
        echo "mkdir $PROJECT_NAME && cd $PROJECT_NAME"
        echo "npm init -y"
        echo "npm install express cors helmet dotenv"
        echo "npm install -D typescript @types/node @types/express ts-node nodemon"
        echo "npx tsc --init"
        [ -n "$DB" ] && [ "$DB" != "none" ] && echo "npm install prisma @prisma/client && npx prisma init"
        ;;
    fastapi)
        echo "mkdir $PROJECT_NAME && cd $PROJECT_NAME"
        echo "python -m venv .venv && source .venv/bin/activate"
        echo "pip install fastapi uvicorn[standard] pydantic-settings"
        [ "$DB" = "postgres" ] && echo "pip install sqlalchemy asyncpg alembic"
        [ "$DB" = "mysql" ] && echo "pip install sqlalchemy aiomysql alembic"
        [ "$DB" = "sqlite" ] && echo "pip install sqlalchemy aiosqlite alembic"
        [ "$DB" = "mongo" ] && echo "pip install motor beanie"
        ;;
    nestjs)
        echo "npx @nestjs/cli new $PROJECT_NAME"
        [ -n "$DB" ] && [ "$DB" != "none" ] && echo "cd $PROJECT_NAME && npm install prisma @prisma/client && npx prisma init"
        ;;
    rn)
        echo "npx create-expo-app@latest $PROJECT_NAME --template tabs"
        echo "cd $PROJECT_NAME && npx expo install expo-router"
        ;;
esac
echo '```'
echo ""

# DB 設定
if [ -n "$DB" ] && [ "$DB" != "none" ]; then
    echo "## DB 設定"
    echo ""
    case "$DB" in
        postgres)
            echo "- **DB**: PostgreSQL"
            echo "- **ORM**: Prisma (Node.js) / SQLAlchemy (Python)"
            echo "- **接続文字列**: \`DATABASE_URL=postgresql://user:password@localhost:5432/$PROJECT_NAME\`"
            echo "- **Docker**: \`docker run -d --name ${PROJECT_NAME}-db -e POSTGRES_PASSWORD=password -p 5432:5432 postgres:16\`"
            ;;
        mysql)
            echo "- **DB**: MySQL"
            echo "- **ORM**: Prisma"
            echo "- **接続文字列**: \`DATABASE_URL=mysql://user:password@localhost:3306/$PROJECT_NAME\`"
            echo "- **Docker**: \`docker run -d --name ${PROJECT_NAME}-db -e MYSQL_ROOT_PASSWORD=password -p 3306:3306 mysql:8\`"
            ;;
        sqlite)
            echo "- **DB**: SQLite"
            echo "- **ORM**: Prisma"
            echo "- **接続文字列**: \`DATABASE_URL=file:./dev.db\`"
            ;;
        mongo)
            echo "- **DB**: MongoDB"
            echo "- **ODM**: Mongoose (Node.js) / Motor+Beanie (Python)"
            echo "- **接続文字列**: \`MONGODB_URI=mongodb://localhost:27017/$PROJECT_NAME\`"
            echo "- **Docker**: \`docker run -d --name ${PROJECT_NAME}-db -p 27017:27017 mongo:7\`"
            ;;
        supabase)
            echo "- **DB**: Supabase (PostgreSQL)"
            echo "- **SDK**: \`@supabase/supabase-js\`"
            echo "- **接続**: Supabase ダッシュボードから URL と anon key を取得"
            ;;
    esac
    echo ""
fi

echo "=============================================="
echo " テンプレート生成完了"
echo "=============================================="
exit 0
