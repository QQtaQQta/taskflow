# Task Tracker API (Vapor + PostgreSQL)

Production-oriented REST API for an iOS task manager (Jira-like, без тяжёлой админки). Stack: **Swift 6.1**, **Vapor 4.121+**, **Fluent**, **PostgreSQL 18**, JWT (access 15m / refresh 30d, rotation), RBAC (admin, manager, assignee, viewer).

## Требования

- Swift 6.1+ (toolchain из Xcode / swift.org)
- PostgreSQL 18 (локально или Docker)

## Локальный запуск

1. Создайте БД и пользователя (или используйте значения из `.env.example`).
2. Скопируйте окружение:

   ```bash
   cp .env.example .env
   ```

3. Убедитесь, что PostgreSQL слушает `DATABASE_HOST` / `DATABASE_PORT`, затем:

   ```bash
   swift run Run
   ```

   Сервер: `http://127.0.0.1:8080` (или `HOSTNAME` / `PORT` из `.env`).

Первая миграция создаёт схему; миграция **SeedRBACAndDemo** (если таблица `roles` пустая) добавляет роли, права, демо-пользователя и проект.

**Демо-логин после сида**

- Email: `admin@demo.local`
- Password: `Password123!`

## Docker Compose

```bash
docker compose up --build
```

- API: `http://localhost:8080`
- PostgreSQL: `localhost:5432` (логин/пароль см. `docker-compose.yml`)

## Тесты

```bash
swift test
```

Сейчас в комплекте **unit-тесты** (без поднятой БД). Для проверки HTTP вручную используйте `curl` или импортируйте `Sources/Application/Resources/openapi/openapi.yaml` в Swagger UI / Stoplight.

## OpenAPI

Файл спецификации: [Sources/Application/Resources/openapi/openapi.yaml](Sources/Application/Resources/openapi/openapi.yaml)

## Общий формат ответа

Успех:

```json
{ "success": true, "data": {}, "meta": null, "error": null }
```

Ошибка:

```json
{
  "success": false,
  "data": null,
  "meta": null,
  "error": { "code": "STRING_CODE", "message": "…", "details": [] }
}
```

Список: `meta.page`, `meta.perPage`, `meta.total` (где применимо).

Заголовок авторизации: `Authorization: Bearer <accessToken>` (кроме `POST /auth/login`, `POST /auth/refresh`, `GET /api/v1/health`).

---

## Полная спецификация методов API (`/api/v1`)

Ниже для каждого метода: **назначение**, **тело/параметры**, **пример ответа** (поле `data` внутри envelope; статусы: 200, 201, 4xx по смыслу).

### AUTH

1. **POST** `/auth/login` — вход.  
   **Body:** `{ "email": "ivan.petrov@company.com", "password": "Password123!" }`  
   **200 data:** `{ "user": { "id", "email", "fullName", "role": { "id", "name" } }, "accessToken", "refreshToken" }`

2. **POST** `/auth/refresh` — обновление пары токенов (refresh rotation).  
   **Body:** `{ "refreshToken": "…" }`  
   **200 data:** `{ "accessToken", "refreshToken" }`

3. **POST** `/auth/logout` — отзыв refresh (jti). Заголовок Bearer access.  
   **Body:** `{ "refreshToken": "…" }`  
   **200 data:** `{ "message": "Logged out" }`

4. **GET** `/auth/me` — текущий пользователь и плоский список прав.  
   **200 data:** `{ "id", "email", "fullName", "avatarUrl", "role": { "id", "name" }, "permissions": ["project.create", …] }`

### ROLES

5. **GET** `/roles` — список ролей. Query: `page`, `perPage`, `sortBy`, `sortOrder`, `search`.  
   **200 data:** массив `{ "id", "name", "description" }`, **meta:** page/perPage/total.

6. **POST** `/roles` — создать роль (admin).  
   **Body:** `{ "name": "qa", "description": "…" }`  
   **201 data:** `{ "id", "name", "description" }`

7. **PATCH** `/roles/{id}` — частичное обновление.  
   **Body:** `{ "name"?, "description"? }`  
   **200 data:** `{ "id", "name", "description" }`

8. **PUT** `/roles/{id}/permissions` — заменить набор прав.  
   **Body:** `{ "permissions": ["project.view", …] }`  
   **200 data:** `{ "roleId", "permissions": […] }`

9. **DELETE** `/roles/{id}` — удалить роль (если не назначена пользователям).  
   **200 data:** `{ "message": "Role deleted" }`

### USERS

10. **GET** `/users` — список. Query: `page`, `perPage`, `search`, `roleId`, сортировка.  
    **200 data:** `[{ "id", "email", "fullName", "isActive", "role": { "id", "name" } }]`, **meta** пагинация.

11. **POST** `/users` — создать пользователя (`user.manage`).  
    **Body:** `{ "email", "password", "fullName", "roleId", "isActive"? }`  
    **201 data:** как в п.10 элемент.

12. **GET** `/users/{id}` — карточка пользователя + `projectsCount`.  
    **200 data:** `{ "id", "email", "fullName", "avatarUrl", "isActive", "role", "projectsCount" }`

13. **PATCH** `/users/{id}` — частичное обновление (без смены пароля в этом DTO).  
    **Body:** `{ "fullName"?, "avatarUrl"?, "roleId"?, "isActive"? }`  
    **200 data:** `{ "id", "email", "fullName", "avatarUrl", "isActive" }`

14. **DELETE** `/users/{id}` — soft delete (`deleted_at`, `isActive=false`).  
    **200 data:** `{ "message": "User archived" }`

### PROJECTS

15. **GET** `/projects` — список доступных проектов, пагинация/поиск.  
    **200 data:** `[{ "id", "key", "name", "description", "isArchived" }]`

16. **POST** `/projects` — создать (`project.create`). Владелец = текущий пользователь.  
    **Body:** `{ "key", "name", "description" }`  
    **201 data:** объект проекта.

17. **GET** `/projects/{id}` — детали + счётчики.  
    **200 data:** `{ "id", "key", "name", "description", "owner": { "id", "fullName" }, "membersCount", "tasksCount", "epicsCount", "boardsCount", "isArchived" }`

18. **PATCH** `/projects/{id}` — частичное обновление.  
    **Body:** `{ "name"?, "description"? }`  
    **200 data:** как в п.15 элемент.

19. **DELETE** `/projects/{id}` — архив (`isArchived=true`).  
    **200 data:** `{ "message": "Project archived" }`

20. **POST** `/projects/{id}/members` — участник.  
    **Body:** `{ "userId", "roleId" }`  
    **201 data:** `{ "projectId", "userId", "roleId" }`

21. **DELETE** `/projects/{id}/members/{userId}` — исключить.  
    **200 data:** `{ "message": "Member removed" }`

### EPICS

22. **GET** `/projects/{projectId}/epics` — список эпиков проекта (пагинация/поиск).  
    **200 data:** `[{ "id", "projectId", "key", "title", "status" }]`

23. **POST** `/projects/{projectId}/epics` — создать.  
    **Body:** `{ "key", "title", "description", "startDate"?, "dueDate"? }`  
    **201 data:** полный объект эпика со статусом по умолчанию `open`.

24. **GET** `/epics/{id}` — детали + `progress`, `tasksCount`, `doneTasksCount`.  
    **200 data:** см. ТЗ (поля эпика + прогресс).

25. **PATCH** `/epics/{id}` — частичное обновление.  
    **Body:** `{ "title"?, "description"?, "status"?, "startDate"?, "dueDate"? }`  
    **200 data:** возвращаются обновлённые поля (минимум `id`, `title`, `status`).

26. **DELETE** `/epics/{id}` — архив.  
    **200 data:** `{ "message": "Epic archived" }`

27. **POST** `/epics/{id}/tasks/{taskId}` — привязать задачу (`task.epic_id`).  
    **200 data:** `{ "epicId", "taskId" }`

28. **DELETE** `/epics/{id}/tasks/{taskId}` — отвязать.  
    **200 data:** `{ "message": "Task unlinked from epic" }`

### TASKS

29. **GET** `/tasks` — фильтры: `projectId`, `assigneeId`, `status`, `epicId`, `search`, пагинация.  
    **200 data:** `[{ "id", "key", "title", "status", "priority", "assignee"?, "estimateMinutes", "spentMinutes" }]`

30. **POST** `/tasks` — создать; `key` генерируется `{PROJECT_KEY}-{nextTaskNumber}`.  
    **Body:** `{ "projectId", "epicId"?, "parentTaskId"?, "title", "description", "issueType", "priority", "assigneeId"?, "reporterId", "estimateMinutes", "dueDate"? }`  
    **201 data:** полная задача + `status: "todo"`, `spentMinutes: 0`, `createdAt`, `updatedAt`.

31. **GET** `/tasks/{id}` — детали + вложенные мини-DTO проекта/эпика, счётчики.  
    **200 data:** см. ТЗ.

32. **PATCH** `/tasks/{id}` — partial update.  
    **Body:** `{ "title"?, "description"?, "priority"?, "dueDate"? }`  
    **200 data:** изменённые поля.

33. **DELETE** `/tasks/{id}` — архив.  
    **200 data:** `{ "message": "Task archived" }`

34. **POST** `/tasks/{id}/assign` — назначение.  
    **Body:** `{ "assigneeId" }`  
    **200 data:** `{ "taskId", "assigneeId" }` (+ уведомление `task_assigned`).

35. **POST** `/tasks/{id}/estimate` — оценка в минутах.  
    **Body:** `{ "estimateMinutes" }`  
    **200 data:** `{ "taskId", "estimateMinutes" }`

36. **POST** `/tasks/{id}/status` — смена статуса; опционально создаётся комментарий.  
    **Body:** `{ "status", "comment"? }`  
    **200 data:** `{ "taskId", "status" }`

37. **POST** `/tasks/{id}/subtasks` — подзадача (`parentTaskId` = id).  
    **Body:** `{ "title", "description"?, "issueType", "assigneeId"?, "estimateMinutes"? }`  
    **201 data:** `{ "id", "parentTaskId", "title", "estimateMinutes" }`

38. **GET** `/tasks/{id}/subtasks` — список подзадач.  
    **200 data:** `[{ "id", "title", "status" }]`

### COMMENTS

39. **GET** `/tasks/{id}/comments`  
    **200 data:** `[{ "id", "author": { "id", "fullName" }, "body", "createdAt" }]`

40. **POST** `/tasks/{id}/comments`  
    **Body:** `{ "body" }`  
    **201 data:** `{ "id", "taskId", "authorId", "body" }`

### TIME ENTRIES

41. **GET** `/tasks/{id}/time-entries`  
    **200 data:** массив записей с `spentMinutes`, `comment`, `startedAt`.

42. **POST** `/tasks/{id}/time-entries` — списание минут; пересчитывает `tasks.spent_minutes`.  
    **Body:** `{ "spentMinutes", "comment", "startedAt" }`  
    **201 data:** созданная запись.

43. **PATCH** `/time-entries/{id}` — автор или admin.  
    **Body:** `{ "spentMinutes"?, "comment"? }`  
    **200 data:** `{ "id", "spentMinutes", "comment" }`

44. **DELETE** `/time-entries/{id}`  
    **200 data:** `{ "message": "Time entry deleted" }`

### BOARDS / KANBAN

45. **GET** `/boards` — опционально `?projectId=`.  
    **200 data:** `[{ "id", "projectId", "name", "isDefault" }]`

46. **POST** `/boards`  
    **Body:** `{ "projectId", "name", "description", "isDefault"? }`  
    **201 data:** объект доски.

47. **GET** `/boards/{id}` — колонки упорядочены по `orderIndex`.  
    **200 data:** `{ "id", "projectId", "name", "columns": […] }`

48. **PATCH** `/boards/{id}`  
    **Body:** `{ "name"?, "description"? }`  
    **200 data:** `{ "id", "name", "description" }`

49. **DELETE** `/boards/{id}` — архив.  
    **200 data:** `{ "message": "Board archived" }`

50. **GET** `/boards/{id}/columns`  
    **200 data:** массив колонок.

51. **POST** `/boards/{id}/columns`  
    **Body:** `{ "name", "key", "orderIndex", "wipLimit"?, "isDoneColumn"? }`  
    **201 data:** колонка с `boardId`.

52. **PATCH** `/columns/{id}`  
    **Body:** `{ "name"?, "orderIndex"?, "wipLimit"? }`  
    **200 data:** `{ "id", "name", "orderIndex", "wipLimit" }`

53. **DELETE** `/columns/{id}`  
    **200 data:** `{ "message": "Column deleted" }`

54. **POST** `/boards/{id}/tasks/{taskId}/move` — колонка + порядок; проверка WIP.  
    **Body:** `{ "boardColumnId", "orderIndex" }`  
    **200 data:** `{ "taskId", "boardId", "boardColumnId", "orderIndex" }`

55. **POST** `/boards/{id}/tasks/{taskId}/reorder`  
    **Body:** `{ "orderIndex" }`  
    **200 data:** `{ "taskId", "orderIndex" }`

### NOTIFICATIONS

56. **GET** `/notifications` — до 200 последних для текущего пользователя.  
    **200 data:** `[{ "id", "type", "title", "body", "isRead", "createdAt" }]`

57. **PATCH** `/notifications/{id}/read`  
    **200 data:** `{ "id", "isRead": true }`

58. **POST** `/notifications/read-all`  
    **200 data:** `{ "message": "All notifications marked as read" }`

### SEARCH

59. **GET** `/search` — `q`, опционально `type` = `project|epic|task|user`.  
    **200 data:** `{ "projects": [], "epics": [], "tasks": [], "users": [] }`

### HEALTH

60. **GET** `/health`  
    **200 data:** `{ "status": "ok", "service": "api", "database": "connected"|"disconnected" }`

---

## Пример вызова

```bash
curl -s http://127.0.0.1:8080/api/v1/health | jq .
TOKEN=$(curl -s -X POST http://127.0.0.1:8080/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@demo.local","password":"Password123!"}' | jq -r '.data.accessToken')
curl -s http://127.0.0.1:8080/api/v1/auth/me -H "Authorization: Bearer $TOKEN" | jq .
```

## Архитектура репозитория

- `Sources/Application/configure.swift`, `routes.swift`
- `Controllers/`, `Services/`, `Models/`, `Migrations/`, `DTOs/`, `Middlewares/`, `Auth/`, `Utilities/`
- Доменная модель задачи: Fluent `WorkTask` → таблица `tasks` (избегаем конфликта со Swift `Task`).

## Лицензия

Дипломный / учебный проект — укажите свою лицензию при публикации.
