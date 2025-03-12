# Cheatsheet de Git en Linux: De Novato a Experto

## 🌱 Nivel Principiante

### Configuración Inicial
```bash
# Configurar nombre y email
git config --global user.name "Tu Nombre"
git config --global user.email "tu@email.com"

# Ver configuración
git config --list
```

### Comandos Básicos
```bash
# Iniciar un repositorio
git init

# Clonar un repositorio existente
git clone https://github.com/usuario/repositorio.git

# Ver estado del repositorio
git status

# Añadir archivos al área de preparación
git add archivo.txt       # Archivo específico
git add .                 # Todos los archivos

# Hacer un commit
git commit -m "Mensaje descriptivo"

# Ver historial de commits
git log
git log --oneline         # Formato resumido

# Subir cambios al repositorio remoto
git push origin main

# Actualizar tu repositorio local
git pull origin main
```

## 🌿 Nivel Intermedio

### Ramas (Branches)
```bash
# Ver ramas
git branch                # Locales
git branch -r             # Remotas
git branch -a             # Todas

# Crear una rama
git branch nueva-rama

# Cambiar a una rama
git checkout nueva-rama

# Crear y cambiar a una nueva rama (atajo)
git checkout -b nueva-rama

# Fusionar ramas
git checkout main         # Cambiar a la rama destino
git merge nueva-rama      # Fusionar rama origen en la actual

# Eliminar rama
git branch -d nueva-rama  # Local
git push origin --delete nueva-rama  # Remota
```

### Trabajando con Cambios
```bash
# Ver diferencias
git diff                  # Cambios no preparados
git diff --staged         # Cambios preparados

# Quitar archivo del área de preparación
git restore --staged archivo.txt

# Descartar cambios locales
git restore archivo.txt

# Corregir último commit
git commit --amend -m "Mensaje corregido"

# Ignorar archivos (.gitignore)
echo "logs/" >> .gitignore
echo "*.tmp" >> .gitignore
```

### Repositorios Remotos
```bash
# Ver repositorios remotos
git remote -v

# Añadir repositorio remoto
git remote add origin https://github.com/usuario/repo.git

# Cambiar URL del remoto
git remote set-url origin https://github.com/usuario/nuevo-repo.git

# Obtener cambios sin fusionar
git fetch origin
```

## 🌳 Nivel Avanzado

### Rebase y Historial
```bash
# Rebase (alternativa a merge)
git checkout feature
git rebase main

# Rebase interactivo (para limpiar historial)
git rebase -i HEAD~3     # Últimos 3 commits

# Cherry-pick (traer commits específicos)
git cherry-pick a1b2c3d4

# Guardar cambios temporalmente
git stash save "Descripción del stash"
git stash list
git stash apply stash@{0}
git stash drop stash@{0}
git stash pop            # Apply + drop
```

### Etiquetas (Tags)
```bash
# Crear etiqueta
git tag v1.0.0
git tag -a v1.0.0 -m "Versión 1.0.0"

# Listar etiquetas
git tag

# Publicar etiquetas
git push origin v1.0.0
git push origin --tags

# Borrar etiqueta
git tag -d v1.0.0
git push origin --delete v1.0.0
```

### Solución de Problemas
```bash
# Buscar en qué commit se introdujo un bug
git bisect start
git bisect bad            # Commit actual tiene el problema
git bisect good v1.0.0    # Este commit estaba bien
# Git te irá llevando a commits para que los pruebes
# Marca cada uno con 'git bisect good' o 'git bisect bad'
git bisect reset          # Finalizar búsqueda

# Reescribir historial (¡peligroso!)
git filter-branch --force --tree-filter 'rm -f contraseñas.txt' HEAD
```

## 🚀 Nivel Experto

### Submódulos
```bash
# Añadir submódulo
git submodule add https://github.com/usuario/libreria.git libs/libreria

# Inicializar submódulos (tras clonar)
git submodule init
git submodule update

# Clonar repo con submódulos
git clone --recursive https://github.com/usuario/proyecto.git

# Actualizar submódulos
git submodule update --remote
```

### Hooks
```bash
# Ubicación
cd .git/hooks/

# Ejemplo de pre-commit hook
cat > .git/hooks/pre-commit << 'EOF'
#!/bin/bash
echo "Ejecutando tests antes del commit..."
npm test
if [ $? -ne 0 ]; then
    echo "Tests fallidos. Commit abortado."
    exit 1
fi
EOF
chmod +x .git/hooks/pre-commit
```

### Git Flow y Estrategias Avanzadas
```bash
# Instalar Git Flow
apt-get install git-flow

# Iniciar Git Flow en un repositorio
git flow init

# Crear feature branch
git flow feature start nueva-funcionalidad

# Finalizar feature
git flow feature finish nueva-funcionalidad

# Crear release
git flow release start v1.2.0
git flow release finish v1.2.0
```

### Optimización y Mantenimiento
```bash
# Verificar integridad del repositorio
git fsck

# Limpiar objetos no referenciados
git gc

# Comprimir repositorio
git gc --aggressive

# Verificar qué archivos ocupan más espacio
git count-objects -v

# Buscar archivos grandes en la historia
git rev-list --objects --all | git cat-file --batch-check='%(objecttype) %(objectname) %(objectsize) %(rest)' | awk '/^blob/ {print substr($0,6)}' | sort -n
```

## 🧠 Consejos de Profesionales

1. **Mensajes de commit efectivos**: Usa el formato "Tipo: Breve descripción" (ej. "Fix: Corrige error en autenticación")

2. **Commits atómicos**: Cada commit debe representar un cambio lógico único.

3. **Nunca reescribas la historia pública**: No uses `--force` en ramas compartidas.

4. **Usa aliases para comandos comunes**:
   ```bash
   git config --global alias.co checkout
   git config --global alias.br branch
   git config --global alias.st status
   git config --global alias.lg "log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit"
   ```

5. **Usa Git integrado con herramientas gráficas**:
   ```bash
   gitk                    # Visualizador incluido
   sudo apt install gitg   # Git GUI para GNOME
   sudo apt install git-cola # Otra alternativa visual
   ```

6. **Mantén actualizadas las herramientas**:
   ```bash
   sudo apt update && sudo apt install git
   ```

7. **Usa firma GPG para verificar la autoría**:
   ```bash
   git config --global commit.gpgsign true
   git config --global user.signingkey TU_ID_CLAVE_GPG
   ```

8. **Usa branch protection y code review** en proyectos colaborativos.

9. **Aprende a usar git worktree** para trabajar en múltiples ramas simultáneamente:
   ```bash
   git worktree add ../branch-folder branch-name
   ```

10. **Automatiza con CI/CD**: Integra Git con Jenkins, GitHub Actions o GitLab CI.
