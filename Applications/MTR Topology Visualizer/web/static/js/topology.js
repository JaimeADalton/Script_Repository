// Topology Visualization using D3.js
document.addEventListener('DOMContentLoaded', function() {
    'use strict';
    
    // Referencias a elementos DOM
    const svg = document.getElementById('topology-graph');
    const tooltip = document.getElementById('tooltip');
    const loading = document.getElementById('loading');
    const groupSelect = document.getElementById('group-select');
    const agentSelect = document.getElementById('agent-select');
    const refreshBtn = document.getElementById('refresh-btn');
    const manageBtn = document.getElementById('manage-btn');
    const managementPanel = document.getElementById('management-panel');
    const closeModalBtn = document.getElementById('close-modal');
    const addAgentBtn = document.getElementById('add-agent-btn');
    const discoverBtn = document.getElementById('discover-btn');
    const statusIndicator = document.getElementById('status-indicator');
    const filterForm = document.getElementById('filter-form');
    const errorMessage = document.getElementById('error-message');
    
    // Estado global
    const state = {
        topologyData: null,
        simulation: null,
        agentsData: [],
        groupsData: [],
        lastUpdate: null,
        refreshInterval: null,
        autoRefresh: false,
        autoRefreshInterval: 60000, // 1 minuto en ms
        selectedGroup: 'all',
        selectedAgent: 'all',
        zoomLevel: 1
    };
    
    // Inicialización
    init();
    
    /**
     * Inicializa la aplicación
     */
    function init() {
        // Configurar event listeners
        setupEventListeners();
        
        // Cargar configuración
        loadConfig();
        
        // Cargar datos iniciales
        loadAgents();
        loadTopologyData();
        
        // Configurar auto-refresh si está habilitado
        setupAutoRefresh();
        
        // Mostrar estadísticas iniciales
        updateStatusIndicator();
    }
    
    /**
     * Configura todos los listeners de eventos
     */
    function setupEventListeners() {
        refreshBtn.addEventListener('click', function() {
            loadTopologyData(true);
        });
        
        manageBtn.addEventListener('click', showManagementPanel);
        closeModalBtn.addEventListener('click', hideManagementPanel);
        addAgentBtn.addEventListener('click', addAgent);
        discoverBtn.addEventListener('click', discoverTelegrafAgents);
        
        // Manejar cambios en los filtros con un solo evento en el formulario
        if (filterForm) {
            filterForm.addEventListener('change', function(e) {
                if (e.target.id === 'group-select') {
                    state.selectedGroup = e.target.value;
                    populateAgentSelect(state.selectedGroup);
                } else if (e.target.id === 'agent-select') {
                    state.selectedAgent = e.target.value;
                }
                
                // Recargar la topología con los nuevos filtros
                loadTopologyData();
            });
        }
        
        // Event listener para toggle de auto-refresh
        const autoRefreshToggle = document.getElementById('auto-refresh-toggle');
        if (autoRefreshToggle) {
            autoRefreshToggle.addEventListener('change', function() {
                state.autoRefresh = this.checked;
                saveConfig();
                setupAutoRefresh();
            });
        }
        
        // Manejar presionado de teclas
        document.addEventListener('keydown', function(e) {
            // Cerrar modal con Escape
            if (e.key === 'Escape' && !managementPanel.classList.contains('hidden')) {
                hideManagementPanel();
            }
            
            // Refrescar con F5 sin recargar la página
            if (e.key === 'F5' && !e.ctrlKey) {
                e.preventDefault();
                loadTopologyData(true);
            }
        });
        
        // Detectar cambios de tamaño de ventana para responsive
        window.addEventListener('resize', debounce(function() {
            if (state.topologyData) {
                renderTopologyGraph(state.topologyData);
            }
        }, 250));
    }
    
    /**
     * Carga la configuración guardada en localStorage
     */
    function loadConfig() {
        try {
            const savedConfig = localStorage.getItem('mtr_topology_config');
            if (savedConfig) {
                const config = JSON.parse(savedConfig);
                
                // Restaurar estado
                state.autoRefresh = config.autoRefresh || false;
                state.autoRefreshInterval = config.autoRefreshInterval || 60000;
                state.selectedGroup = config.selectedGroup || 'all';
                state.selectedAgent = config.selectedAgent || 'all';
                
                // Aplicar valores a los elementos UI
                const autoRefreshToggle = document.getElementById('auto-refresh-toggle');
                if (autoRefreshToggle) {
                    autoRefreshToggle.checked = state.autoRefresh;
                }
                
                const intervalSelect = document.getElementById('refresh-interval');
                if (intervalSelect && config.autoRefreshInterval) {
                    intervalSelect.value = (config.autoRefreshInterval / 1000).toString();
                }
            }
        } catch (error) {
            console.error('Error loading config:', error);
            // Usar valores predeterminados en caso de error
        }
    }
    
    /**
     * Guarda la configuración actual en localStorage
     */
    function saveConfig() {
        try {
            const config = {
                autoRefresh: state.autoRefresh,
                autoRefreshInterval: state.autoRefreshInterval,
                selectedGroup: state.selectedGroup,
                selectedAgent: state.selectedAgent
            };
            
            localStorage.setItem('mtr_topology_config', JSON.stringify(config));
        } catch (error) {
            console.error('Error saving config:', error);
        }
    }
    
    /**
     * Configura el auto-refresh según el estado actual
     */
    function setupAutoRefresh() {
        // Limpiar intervalo existente
        if (state.refreshInterval) {
            clearInterval(state.refreshInterval);
            state.refreshInterval = null;
        }
        
        // Configurar nuevo intervalo si está habilitado
        if (state.autoRefresh) {
            state.refreshInterval = setInterval(function() {
                loadTopologyData(false); // Sin mostrar mensaje de loading
            }, state.autoRefreshInterval);
            
            // Actualizar texto del botón
            refreshBtn.innerHTML = '<span class="icon">⟳</span> Auto-refresh ON';
        } else {
            refreshBtn.innerHTML = '<span class="icon">⟳</span> Refresh';
        }
    }
    
    /**
     * Utility: debounce function para evitar llamadas excesivas
     */
    function debounce(func, delay) {
        let timeout;
        return function() {
            const context = this;
            const args = arguments;
            clearTimeout(timeout);
            timeout = setTimeout(() => func.apply(context, args), delay);
        };
    }
    
    /**
     * Muestra un mensaje de error
     */
    function showError(message, timeout = 5000) {
        if (!errorMessage) return;
        
        errorMessage.textContent = message;
        errorMessage.style.display = 'block';
        
        // Auto-ocultar después de un tiempo
        if (timeout) {
            setTimeout(() => {
                errorMessage.style.display = 'none';
            }, timeout);
        }
    }
    
    /**
     * Actualiza el indicador de estado
     */
    function updateStatusIndicator() {
        if (!statusIndicator) return;
        
        fetch('/api/stats')
            .then(response => {
                if (!response.ok) {
                    throw new Error('Error fetching stats');
                }
                return response.json();
            })
            .then(data => {
                if (data.success && data.stats) {
                    const stats = data.stats;
                    statusIndicator.innerHTML = `
                        <span>Agents: ${stats.enabled_agents}/${stats.total_agents}</span>
                        <span>Scan interval: ${formatTime(stats.scan_interval)}</span>
                        ${state.lastUpdate ? `<span>Last update: ${formatDateTime(state.lastUpdate)}</span>` : ''}
                    `;
                }
            })
            .catch(error => {
                console.error('Error:', error);
            });
    }
    
    /**
     * Formatea un tiempo en segundos a formato legible
     */
    function formatTime(seconds) {
        if (seconds < 60) {
            return `${seconds}s`;
        } else if (seconds < 3600) {
            return `${Math.floor(seconds / 60)}m`;
        } else {
            return `${Math.floor(seconds / 3600)}h ${Math.floor((seconds % 3600) / 60)}m`;
        }
    }
    
    /**
     * Formatea una fecha en formato legible
     */
    function formatDateTime(dateStr) {
        try {
            const date = new Date(dateStr);
            return date.toLocaleString();
        } catch (e) {
            return dateStr;
        }
    }
    
    /**
     * Carga la lista de agentes desde la API
     */
    async function loadAgents() {
        loading.style.display = 'block';
        
        try {
            const response = await fetch('/api/agents');
            
            if (!response.ok) {
                throw new Error('Error loading agents');
            }
            
            state.agentsData = await response.json();
            
            // Cargar grupos
            const groupResponse = await fetch('/api/groups');
            if (groupResponse.ok) {
                state.groupsData = await groupResponse.json();
            } else {
                // Extraer grupos únicos de los agentes
                state.groupsData = [...new Set(state.agentsData.map(agent => agent.group))];
            }
            
            // Poblar selects
            populateGroupSelect();
            populateAgentSelect(state.selectedGroup);
            
            // Si estamos en la vista de gestión, también actualizar la tabla
            if (!managementPanel.classList.contains('hidden')) {
                populateAgentsTable();
            }
            
        } catch (error) {
            console.error('Error:', error);
            showError('Error loading agents: ' + error.message);
        } finally {
            loading.style.display = 'none';
        }
    }
    
    /**
     * Actualiza el select de grupos
     */
    function populateGroupSelect() {
        if (!groupSelect) return;
        
        // Backup current value
        const currentValue = groupSelect.value;
        
        // Clear options except "All"
        while (groupSelect.options.length > 1) {
            groupSelect.remove(1);
        }
        
        // Add groups
        state.groupsData.forEach(group => {
            if (!group) return; // Skip null/empty groups
            
            const option = document.createElement('option');
            option.value = group;
            option.textContent = group;
            groupSelect.appendChild(option);
        });
        
        // Restore selected value if it still exists, otherwise default to 'all'
        if (currentValue && [...groupSelect.options].some(opt => opt.value === currentValue)) {
            groupSelect.value = currentValue;
        } else {
            groupSelect.value = 'all';
            state.selectedGroup = 'all';
        }
    }
    
    /**
     * Actualiza el select de agentes
     */
    function populateAgentSelect(selectedGroup = null) {
        if (!agentSelect) return;
        
        // Backup current value
        const currentValue = agentSelect.value;
        
        // Clear options except "All"
        while (agentSelect.options.length > 1) {
            agentSelect.remove(1);
        }
        
        // Filter agents by group if selected
        const filteredAgents = selectedGroup && selectedGroup !== 'all'
            ? state.agentsData.filter(agent => agent.group === selectedGroup)
            : state.agentsData;
        
        // Add agents
        filteredAgents.forEach(agent => {
            const option = document.createElement('option');
            option.value = agent.address;
            option.textContent = agent.name || agent.address;
            agentSelect.appendChild(option);
        });
        
        // Restore selected value if it still exists, otherwise default to 'all'
        if (currentValue && [...agentSelect.options].some(opt => opt.value === currentValue)) {
            agentSelect.value = currentValue;
            state.selectedAgent = currentValue;
        } else {
            agentSelect.value = 'all';
            state.selectedAgent = 'all';
        }
    }
    
    /**
     * Actualiza la tabla de agentes en el panel de gestión
     */
    function populateAgentsTable() {
        const tbody = document.querySelector('#agents-table tbody');
        if (!tbody) return;
        
        tbody.innerHTML = '';
        
        state.agentsData.forEach(agent => {
            const row = document.createElement('tr');
            
            // Status class based on last scan success
            const statusClass = agent.enabled 
                ? (agent.last_scan_success ? 'active' : 'warning')
                : 'inactive';
            
            // Status text
            const statusText = agent.enabled
                ? (agent.last_scan_success ? 'Active' : 'Error')
                : 'Disabled';
            
            // Last scan time
            const lastScan = agent.last_scan 
                ? new Date(agent.last_scan).toLocaleString()
                : 'Never';
            
            // Celdas con información del agente
            row.innerHTML = `
                <td>${agent.address}</td>
                <td>${agent.name || agent.address}</td>
                <td>${agent.group || 'default'}</td>
                <td>
                    <span class="status-indicator ${statusClass}">
                        ${statusText}
                    </span>
                </td>
                <td>${lastScan}</td>
                <td class="actions">
                    <button class="button small scan-btn" data-address="${agent.address}">
                        <span class="icon">🔄</span>
                    </button>
                    <button class="button small toggle-btn ${agent.enabled ? 'warning' : 'primary'}" data-address="${agent.address}" data-enabled="${agent.enabled}">
                        ${agent.enabled ? 'Disable' : 'Enable'}
                    </button>
                    <button class="button small danger remove-btn" data-address="${agent.address}">
                        <span class="icon">🗑️</span>
                    </button>
                </td>
            `;
            
            tbody.appendChild(row);
        });
        
        // Añadir event listeners a los botones
        document.querySelectorAll('.scan-btn').forEach(btn => {
            btn.addEventListener('click', function() {
                const address = this.dataset.address;
                scanAgent(address);
            });
        });
        
        document.querySelectorAll('.toggle-btn').forEach(btn => {
            btn.addEventListener('click', function() {
                const address = this.dataset.address;
                const enabled = this.dataset.enabled === 'true';
                toggleAgent(address, !enabled);
            });
        });
        
        document.querySelectorAll('.remove-btn').forEach(btn => {
            btn.addEventListener('click', function() {
                const address = this.dataset.address;
                removeAgent(address);
            });
        });
    }
    
    /**
     * Carga los datos de topología desde la API
     */
    async function loadTopologyData(showLoading = true) {
        if (showLoading) {
            loading.style.display = 'block';
        }
        
        try {
            // Construir URL con filtros
            let url = '/api/topology';
            const params = [];
            
            if (state.selectedGroup && state.selectedGroup !== 'all') {
                params.push(`group=${encodeURIComponent(state.selectedGroup)}`);
            }
            
            if (state.selectedAgent && state.selectedAgent !== 'all') {
                params.push(`agent=${encodeURIComponent(state.selectedAgent)}`);
            }
            
            if (params.length > 0) {
                url += '?' + params.join('&');
            }
            
            const response = await fetch(url);
            
            if (!response.ok) {
                throw new Error('Error loading topology data');
            }
            
            state.topologyData = await response.json();
            state.lastUpdate = new Date().toISOString();
            
            renderTopologyGraph(state.topologyData);
            updateStatusIndicator();
            
        } catch (error) {
            console.error('Error:', error);
            showError('Error loading topology: ' + error.message);
        } finally {
            loading.style.display = 'none';
        }
    }
    
    /**
     * Renderiza el grafo de topología usando D3.js
     */
    function renderTopologyGraph(data) {
        if (!svg) return;
        
        if (!data || !data.nodes || !data.links || data.nodes.length === 0) {
            showEmptyMessage();
            return;
        }
        
        // Limpiar SVG existente
        const d3svg = d3.select(svg);
        d3svg.selectAll("*").remove();
        
        // Dimensiones
        const width = svg.clientWidth || 800;
        const height = svg.clientHeight || 600;
        
        // Tooltips
        function showTooltip(event, content) {
            tooltip.innerHTML = content;
            tooltip.style.display = 'block';
            
            // Posicionamiento inteligente para evitar salir de la ventana
            const tooltipWidth = tooltip.offsetWidth;
            const tooltipHeight = tooltip.offsetHeight;
            const windowWidth = window.innerWidth;
            const windowHeight = window.innerHeight;
            
            let left = event.pageX + 10;
            let top = event.pageY - 10;
            
            // Ajustar si se sale por la derecha
            if (left + tooltipWidth > windowWidth - 20) {
                left = event.pageX - tooltipWidth - 10;
            }
            
            // Ajustar si se sale por abajo
            if (top + tooltipHeight > windowHeight - 20) {
                top = event.pageY - tooltipHeight - 10;
            }
            
            tooltip.style.left = `${left}px`;
            tooltip.style.top = `${top}px`;
        }
        
        function hideTooltip() {
            tooltip.style.display = 'none';
        }
        
        // Escalas para visualización
        const linkWidthScale = d3.scaleLinear()
            .domain([1, d3.max(data.links, d => d.destinations.length) || 1])
            .range([2, 8]);
        
        const lossColorScale = d3.scaleThreshold()
            .domain([0.1, 1, 5, 10])
            .range(["#38a169", "#ecc94b", "#ed8936", "#e53e3e"]);
        
        // Configurar simulación de fuerzas
        state.simulation = d3.forceSimulation(data.nodes)
            .force("link", d3.forceLink(data.links)
                .id(d => d.id)
                .distance(d => 100 + (d.source.type === "source" || d.target.type === "destination" ? 50 : 0)))
            .force("charge", d3.forceManyBody()
                .strength(d => d.type === "source" || d.type === "destination" ? -800 : -400))
            .force("center", d3.forceCenter(width / 2, height / 2))
            .force("collision", d3.forceCollide().radius(30))
            .force("x", d3.forceX(width / 2).strength(0.05))
            .force("y", d3.forceY(height / 2).strength(0.05));
        
        // Crear contenedores de grupos para renderizado en capas
        const linkGroup = d3svg.append("g").attr("class", "links");
        const nodeGroup = d3svg.append("g").attr("class", "nodes");
        const labelGroup = d3svg.append("g").attr("class", "labels");
        
        // Crear enlaces con estilo mejorado
        const link = linkGroup.selectAll("line")
            .data(data.links)
            .enter()
            .append("line")
            .attr("stroke-width", d => linkWidthScale(d.destinations.length))
            .attr("stroke", d => lossColorScale(d.loss))
            .style("opacity", 0.6)
            .on("mouseover", function(event, d) {
                d3.select(this)
                    .transition()
                    .duration(200)
                    .style("opacity", 1)
                    .attr("stroke-width", d => linkWidthScale(d.destinations.length) * 1.5);
                
                // Preparar lista de destinos (limitar a 10 para no sobrecargar)
                const destinationsList = d.destinations.length <= 10
                    ? d.destinations.map(dest => `<li>${dest}</li>`).join('')
                    : d.destinations.slice(0, 10).map(dest => `<li>${dest}</li>`).join('') + 
                      `<li>... and ${d.destinations.length - 10} more</li>`;
                
                showTooltip(event, `
                    <div class="tooltip-content">
                        <h3>Connection</h3>
                        <p><strong>From:</strong> ${d.source.name || d.source.id}</p>
                        <p><strong>To:</strong> ${d.target.name || d.target.id}</p>
                        <p><strong>Latency:</strong> ${d.latency ? d.latency.toFixed(2) : "N/A"} ms</p>
                        <p><strong>Loss:</strong> ${d.loss ? d.loss.toFixed(2) : "0.00"}%</p>
                        <p><strong>Destinations:</strong> ${d.destinations.length}</p>
                        <div class="tooltip-scroll">
                            <ul class="tooltip-list">${destinationsList}</ul>
                        </div>
                    </div>
                `);
            })
            .on("mouseout", function() {
                d3.select(this)
                    .transition()
                    .duration(200)
                    .style("opacity", 0.6)
                    .attr("stroke-width", d => linkWidthScale(d.destinations.length));
                
                hideTooltip();
            });
        
        // Crear nodos con estilo mejorado
        const node = nodeGroup.selectAll("circle")
            .data(data.nodes)
            .enter()
            .append("circle")
            .attr("r", d => {
                if (d.type === "source") return 15;
                if (d.type === "destination") return 12;
                return 8;
            })
            .attr("fill", d => {
                if (d.type === "source") return "#1a7ad4";
                if (d.type === "destination") return "#38a169";
                return "#718096";
            })
            .style("stroke", "#fff")
            .style("stroke-width", 2)
            .style("cursor", "pointer")
            .on("mouseover", function(event, d) {
                // Aumentar tamaño del nodo
                d3.select(this)
                    .transition()
                    .duration(200)
                    .attr("r", d => {
                        if (d.type === "source") return 18;
                        if (d.type === "destination") return 15;
                        return 10;
                    });
                
                // Resaltar enlaces conectados
                link.style("opacity", function(l) {
                    if (l.source.id === d.id || l.target.id === d.id) {
                        return 1;
                    } else {
                        return 0.1;
                    }
                });
                
                // Encontrar enlaces conectados a este nodo
                const connectedLinks = data.links.filter(l => 
                    l.source.id === d.id || l.target.id === d.id
                );
                
                // Recolectar destinos
                const destinations = new Set();
                connectedLinks.forEach(l => {
                    if (l.destinations) {
                        l.destinations.forEach(dest => destinations.add(dest));
                    }
                });
                
                // Calcular métricas agregadas
                let avgLatency = 0;
                let maxLoss = 0;
                
                if (connectedLinks.length > 0) {
                    avgLatency = connectedLinks.reduce((sum, l) => sum + (l.latency || 0), 0) / connectedLinks.length;
                    maxLoss = Math.max(...connectedLinks.map(l => l.loss || 0));
                }
                
                // Preparar lista de destinos
                let destinationsList = '';
                if (destinations.size > 0) {
                    const destArray = Array.from(destinations);
                    destinationsList = destArray.length <= 10
                        ? destArray.map(dest => `<li>${dest}</li>`).join('')
                        : destArray.slice(0, 10).map(dest => `<li>${dest}</li>`).join('') + 
                          `<li>... and ${destArray.length - 10} more</li>`;
                }
                
                // Crear tooltip con contenido enriquecido
                showTooltip(event, `
                    <div class="tooltip-content">
                        <h3>${d.name || d.id}</h3>
                        <p><strong>IP:</strong> ${d.ip || 'N/A'}</p>
                        <p><strong>Type:</strong> ${
                            d.type === "source" ? "Source (Server)" : 
                            d.type === "destination" ? "Destination (Agent)" : "Router/Hop"
                        }</p>
                        ${avgLatency > 0 ? `<p><strong>Avg Latency:</strong> ${avgLatency.toFixed(2)} ms</p>` : ''}
                        ${maxLoss > 0 ? `<p><strong>Max Loss:</strong> ${maxLoss.toFixed(2)}%</p>` : ''}
                        ${destinations.size > 0 ? `
                            <p><strong>Associated destinations:</strong> ${destinations.size}</p>
                            <div class="tooltip-scroll">
                                <ul class="tooltip-list">${destinationsList}</ul>
                            </div>
                        ` : ''}
                    </div>
                `);
            })
            .on("mouseout", function() {
                // Restaurar tamaño del nodo
                d3.select(this)
                    .transition()
                    .duration(200)
                    .attr("r", d => {
                        if (d.type === "source") return 15;
                        if (d.type === "destination") return 12;
                        return 8;
                    });
                
                // Restaurar opacidad de enlaces
                link.style("opacity", 0.6);
                
                hideTooltip();
            })
            .call(d3.drag()
                .on("start", dragStarted)
                .on("drag", dragging)
                .on("end", dragEnded));
        
        // Etiquetas para los nodos
        const label = labelGroup.selectAll("text")
            .data(data.nodes)
            .enter()
            .append("text")
            .text(d => {
                if (d.type === "source") return "Server";
                if (d.type === "destination") return d.name || d.id;
                // Acortar IP para routers
                return d.name ? d.name.substring(0, 10) : d.ip ? d.ip.substring(0, 10) : '';
            })
            .attr("font-size", d => d.type === "router" ? 8 : 10)
            .attr("text-anchor", "middle")
            .attr("dy", d => d.type === "destination" ? -15 : -12)
            .style("fill", "white")
            .style("filter", "drop-shadow(0px 0px 2px rgba(0,0,0,0.8))")
            .style("pointer-events", "none")
            .style("user-select", "none");
        
        // Funciones para el arrastre de nodos
        function dragStarted(event, d) {
            if (!event.active) state.simulation.alphaTarget(0.3).restart();
            d.fx = d.x;
            d.fy = d.y;
        }
        
        function dragging(event, d) {
            d.fx = event.x;
            d.fy = event.y;
        }
        
        function dragEnded(event, d) {
            if (!event.active) state.simulation.alphaTarget(0);
            // Mantener fijo para origen y destino
            if (d.type !== "router") {
                // No resetear fx y fy para mantener la posición
            } else {
                d.fx = null;
                d.fy = null;
            }
        }
        
        // Organizar posiciones iniciales para mejorar la visualización
        data.nodes.forEach(node => {
            if (node.type === "source") {
                node.fx = width * 0.1;
                node.fy = height / 2;
            } 
            else if (node.type === "destination") {
                // Distribuir destinos verticalmente
                const destNodes = data.nodes.filter(n => n.type === "destination");
                const index = destNodes.indexOf(node);
                const totalDest = destNodes.length;
                
                // Si hay muchos destinos, usar varias columnas
                if (totalDest > 20) {
                    const itemsPerColumn = Math.ceil(totalDest / Math.ceil(totalDest / 20));
                    const column = Math.floor(index / itemsPerColumn);
                    const posInColumn = index % itemsPerColumn;
                    const columnSpacing = width * 0.15;
                    
                    node.fx = width * 0.85 - (column * columnSpacing);
                    node.fy = height * 0.1 + (posInColumn / (itemsPerColumn - 1 || 1)) * height * 0.8;
                } else {
                    node.fx = width * 0.9;
                    node.fy = height * 0.1 + (index / (totalDest - 1 || 1)) * height * 0.8;
                }
            }
        });
        
        // Actualizar posiciones en cada tick
        state.simulation.on("tick", () => {
            link
                .attr("x1", d => d.source.x)
                .attr("y1", d => d.source.y)
                .attr("x2", d => d.target.x)
                .attr("y2", d => d.target.y);
            
            node
                .attr("cx", d => d.x)
                .attr("cy", d => d.y);
            
            label
                .attr("x", d => d.x)
                .attr("y", d => d.y);
        });
        
        // Función para hacer zoom
        const zoom = d3.zoom()
            .scaleExtent([0.1, 3])
            .on("zoom", (event) => {
                nodeGroup.attr("transform", event.transform);
                linkGroup.attr("transform", event.transform);
                labelGroup.attr("transform", event.transform);
                state.zoomLevel = event.transform.k;
            });
        
        d3svg.call(zoom);
        
        // Ajustar zoom inicial para ver todo el grafo
        const initialScale = 0.9;
        d3svg.call(zoom.transform, d3.zoomIdentity
            .translate(width / 2, height / 2)
            .scale(initialScale)
            .translate(-width / 2, -height / 2));
            
        // Añadir controles de zoom
        const zoomControls = d3svg.append("g")
            .attr("class", "zoom-controls")
            .attr("transform", `translate(${width - 50}, 20)`);
            
        zoomControls.append("rect")
            .attr("x", 0)
            .attr("y", 0)
            .attr("width", 30)
            .attr("height", 60)
            .attr("rx", 5)
            .attr("ry", 5)
            .attr("fill", "#4a5568")
            .attr("opacity", 0.7);
            
        // Botón de zoom in
        zoomControls.append("text")
            .attr("x", 15)
            .attr("y", 20)
            .attr("text-anchor", "middle")
            .attr("fill", "white")
            .style("font-size", "18px")
            .style("cursor", "pointer")
            .text("+")
            .on("click", function() {
                d3svg.transition().duration(300).call(
                    zoom.scaleBy, 1.3
                );
            });
            
        // Botón de zoom out
        zoomControls.append("text")
            .attr("x", 15)
            .attr("y", 50)
            .attr("text-anchor", "middle")
            .attr("fill", "white")
            .style("font-size", "18px")
            .style("cursor", "pointer")
            .text("−")
            .on("click", function() {
                d3svg.transition().duration(300).call(
                    zoom.scaleBy, 0.7
                );
            });
            
        // Separador
        zoomControls.append("line")
            .attr("x1", 5)
            .attr("y1", 30)
            .attr("x2", 25)
            .attr("y2", 30)
            .attr("stroke", "white")
            .attr("opacity", 0.5);
    }
    
    /**
     * Muestra un mensaje cuando no hay datos disponibles
     */
    function showEmptyMessage() {
        const d3svg = d3.select(svg);
        d3svg.selectAll("*").remove();
        
        const width = svg.clientWidth || 800;
        const height = svg.clientHeight || 600;
        
        d3svg.append("text")
            .attr("x", width / 2)
            .attr("y", height / 2)
            .attr("text-anchor", "middle")
            .style("fill", "#718096")
            .style("font-size", "20px")
            .text("No data available to display");
            
        d3svg.append("text")
            .attr("x", width / 2)
            .attr("y", (height / 2) + 30)
            .attr("text-anchor", "middle")
            .style("fill", "#718096")
            .style("font-size", "16px")
            .text("Add agents or select a different filter");
    }
    
    // Funciones de gestión de agentes
    
    function showManagementPanel() {
        managementPanel.classList.remove('hidden');
        populateAgentsTable();
    }
    
    function hideManagementPanel() {
        managementPanel.classList.add('hidden');
    }
    
    async function addAgent() {
        const address = document.getElementById('new-agent-ip').value.trim();
        const name = document.getElementById('new-agent-name').value.trim();
        const group = document.getElementById('new-agent-group').value.trim();
        
        if (!address) {
            showError('Please enter a valid IP address');
            return;
        }
        
        try {
            const response = await fetch('/api/agent', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify({ address, name, group })
            });
            
            const data = await response.json();
            
            if (data.success) {
                document.getElementById('new-agent-ip').value = '';
                document.getElementById('new-agent-name').value = '';
                
                showError('Agent added successfully', 3000);
                await loadAgents();
                loadTopologyData();
            } else {
                showError('Error adding agent: ' + (data.error || 'Unknown error'));
            }
        } catch (error) {
            console.error('Error:', error);
            showError('Error adding agent: ' + error.message);
        }
    }
    
    async function scanAgent(address) {
        try {
            const response = await fetch(`/api/scan/${address}`);
            const data = await response.json();
            
            if (data.success) {
                showError(`Agent ${address} scanned successfully`, 3000);
                await loadAgents();
                loadTopologyData();
            } else {
                showError('Error scanning agent: ' + (data.error || 'Unknown error'));
            }
        } catch (error) {
            console.error('Error:', error);
            showError('Error scanning agent: ' + error.message);
        }
    }
    
    async function toggleAgent(address, enable) {
        try {
            const response = await fetch(`/api/agent/${address}`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify({ action: enable ? 'enable' : 'disable' })
            });
            
            const data = await response.json();
            
            if (data.success) {
                showError(`Agent ${address} ${enable ? 'enabled' : 'disabled'} successfully`, 3000);
                await loadAgents();
                loadTopologyData();
            } else {
                showError('Error: ' + (data.error || 'Unknown error'));
            }
        } catch (error) {
            console.error('Error:', error);
            showError('Error: ' + error.message);
        }
    }
    
    async function removeAgent(address) {
        if (!confirm(`Are you sure you want to remove agent ${address}?`)) {
            return;
        }
        
        try {
            const response = await fetch(`/api/agent/${address}`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify({ action: 'remove' })
            });
            
            const data = await response.json();
            
            if (data.success) {
                showError(`Agent ${address} removed successfully`, 3000);
                await loadAgents();
                loadTopologyData();
            } else {
                showError('Error removing agent: ' + (data.error || 'Unknown error'));
            }
        } catch (error) {
            console.error('Error:', error);
            showError('Error removing agent: ' + error.message);
        }
    }
    
    async function discoverTelegrafAgents() {
        const path = document.getElementById('telegraf-path').value.trim();
        
        try {
            const response = await fetch(`/api/discover-telegraf?path=${encodeURIComponent(path)}`);
            const data = await response.json();
            
            if (data.success) {
                showError(`Discovered ${data.agents.length} agents, ${data.added_to_monitoring} added to monitoring`, 5000);
                await loadAgents();
                loadTopologyData();
            } else {
                showError('Error discovering agents: ' + (data.error || 'Unknown error'));
            }
        } catch (error) {
            console.error('Error:', error);
            showError('Error discovering agents: ' + error.message);
        }
    }
});
