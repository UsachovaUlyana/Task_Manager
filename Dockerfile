# Сборка и запуск TaskManager.API в контейнере (используется docker-compose.yml, сервис api)

FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src

# Сначала только csproj — чтобы слой с restore кэшировался между сборками
COPY src/TaskManager.Domain/TaskManager.Domain.csproj src/TaskManager.Domain/
COPY src/TaskManager.Application/TaskManager.Application.csproj src/TaskManager.Application/
COPY src/TaskManager.Infrastructure/TaskManager.Infrastructure.csproj src/TaskManager.Infrastructure/
COPY src/TaskManager.API/TaskManager.API.csproj src/TaskManager.API/
RUN dotnet restore src/TaskManager.API/TaskManager.API.csproj

COPY src/ src/
RUN dotnet publish src/TaskManager.API/TaskManager.API.csproj -c Release -o /app/publish --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS runtime
WORKDIR /app
COPY --from=build /app/publish .

ENV ASPNETCORE_URLS=http://+:8080
EXPOSE 8080

ENTRYPOINT ["dotnet", "TaskManager.API.dll"]
