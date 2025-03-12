// Topology Visualization using D3.js
document.addEventListener('DOMContentLoaded', function() {
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
    
    // Estado global
    let topologyData = null;
    let simulation = null;
    let agentsData = [];
    let groupsData = [];
    
    // Inicialización
    loadAgents();
    loadTopologyData();
    
    // Event listeners
    refreshBtn.addEventListener('click', loadTopologyData);
    manageBtn.addEventListener('click', showManagementPanel);
    closeModalBtn.addEventListener('click', hideManagementPanel);
    addAgentBtn.addEventListener('click', addAgent);
    discoverBtn.addEventListener('click', discoverTelegrafAgents);
    
    groupSelect.addEventListener('change', function() {
        const selectedGroup = groupSelect.value;
        
        // Actualizar lista de agentes basado en el grupo seleccionado
        populateAgentSelect(selectedGroup);
        
        // Recargar topología con el filtro de grupo
        loadTopologyData();
    });
    
    agentSelect.addEventListener('change', function() {
        loadTopologyData();
    });
    
    // Funciones
    
    async function loadAgents() {
        loading.style.display = 'block';
        
        try {
            const response = await fetch('/api/agents');
            
            if (!response.ok) {
                throw new Error('Error al cargar agentes');
            }
            
            agentsData = await response.json();
            
            // Extraer grupos únicos
            groupsData = [...new Set(agentsData.map(agent => agent.group))];
            
            // Poblar selects
            populateGroupSelect();
            populateAgentSelect();
            populateAgentsTable();
            
        } catch (error) {
            console.error('Error:', error);
            alert('Error al cargar agentes: ' + error.message);
        } finally {
            loading.style.display = 'none';
        }
    }
    
    function populateGroupSelect() {
        // Limpiar opciones actuales excepto "Todos"
        while (groupSelect.options.length > 1) {
            groupSelect.remove(1);
        }
        
        // Añadir grupos
        groupsData.forEach(group => {
            const option = document.createElement('option');
            option.value = group;
            option.textContent = group;
            groupSelect.appendChild(option);
        });
    }
    
    function populateAgentSelect(selectedGroup = null) {
        // Limpiar opciones actuales excepto "Todos"
        while (agentSelect.options.length > 1) {
            agentSelect.remove(1);
        }
        
        // Filtrar agentes por grupo si se seleccionó uno
        const filteredAgents = selectedGroup && selectedGroup !== 'all'
            ? agentsData.filter(agent => agent.group === selectedGroup)
            : agentsData;
        
        // Añadir agentes
        filteredAgents.forEach(agent => {
            const option = document.createElement('option');
            option.value = agent.address;
            option.textContent = agent.name || agent.address;
            agentSelect.appendChild(option);
        });
    }
    
    function populateAgentsTable() {
        const tbody = document.querySelector('#agents-table tbody');
        tbody.innerHTML = '';
        
        agentsData.forEach(agent => {
            const row = document.createElement('tr');
            
            // Celdas con información del agente
            row.innerHTML = `
                <td>${agent.address}</td>
                <td>${agent.name || agent.address}</td>
                <td>${agent.group || 'default'}</td>
                <td>
                    <span class="status-indicator ${agent.enabled !== false ? 'active' : 'inactive'}">
                        ${agent.enabled !== false ? 'Activo' : 'Inactivo'}
                    </span>
                </td>
                <td class="actions">
                    <button class="button small scan-btn" data-address="${agent.address}">
                        Escanear
                    </button>
                    <button class="button small toggle-btn" data-address="${agent.address}" data-enabled="${agent.enabled !== false}">
                        ${agent.enabled !== false ? 'Deshabilitar' : 'Habilitar'}
                    </button>
                    <button class="button small danger remove-btn" data-address="${agent.address}">
                        Eliminar
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
    
    async function loadTopologyData() {
        loading.style.display = 'block';
        
        try {
            const selectedGroup = groupSelect.value;
            const selectedAgent = agentSelect.value;
            
            // Construir URL con filtros
            let url = '/api/topology';
            const params = [];
            
            if (selectedGroup && selectedGroup !== 'all') {
                params.push(`group=${selectedGroup}`);
            }
            
            if (selectedAgent && selectedAgent !== 'all') {
                params.push(`agent=${selectedAgent}`);
            }
            
            if (params.length > 0) {
                url += '?' + params.join('&');
            }
            
            const response = await fetch(url);
            
            if (!response.ok) {
                throw new Error('Error al cargar datos');
            }
            
            topologyData = await response.json();
            renderTopologyGraph(topologyData);
            
        } catch (error) {
            console.error('Error:', error);
            alert('Error al cargar datos: ' + error.message);
        } finally {
            loading.style.display = 'none';
        }
    }
    
    function renderTopologyGraph(data) {
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
        
        // Crear tooltip mejorado
        function showTooltip(event, content) {
            tooltip.innerHTML = content;
            tooltip.style.display = 'block';
            tooltip.style.left = `${event.pageX + 10}px`;
            tooltip.style.top = `${event.pageY - 10}px`;
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
        
        // Configurar simulación de fuerzas con mejoras para evitar solapamientos
        simulation = d3.forceSimulation(data.nodes)
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
                
                showTooltip(event, `
                    <div class="tooltip-content">
                        <h3>Conexión</h3>
                        <p><strong>Desde:</strong> ${d.source.name || d.source.id}</p>
                        <p><strong>Hacia:</strong> ${d.target.name || d.target.id}</p>
                        <p><strong>Latencia:</strong> ${d.latency ? d.latency.toFixed(2) : "N/A"} ms</p>
                        <p><strong>Pérdida:</strong> ${d.loss ? d.loss.toFixed(2) : "0.00"}%</p>
                        <p><strong>Destinos:</strong> ${d.destinations.length}</p>
                        <ul class="tooltip-list">
                            ${d.destinations.map(dest => `<li>${dest}</li>`).join('')}
                        </ul>
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
                
                // Crear tooltip con contenido enriquecido
                showTooltip(event, `
                    <div class="tooltip-content">
                        <h3>${d.name || d.id}</h3>
                        <p><strong>IP:</strong> ${d.ip || 'N/A'}</p>
                        <p><strong>Tipo:</strong> ${
                            d.type === "source" ? "Origen (Servidor)" : 
                            d.type === "destination" ? "Destino (Agente)" : "Router/Hop"
                        }</p>
                        ${avgLatency > 0 ? `<p><strong>Latencia promedio:</strong> ${avgLatency.toFixed(2)} ms</p>` : ''}
                        ${maxLoss > 0 ? `<p><strong>Pérdida máxima:</strong> ${maxLoss.toFixed(2)}%</p>` : ''}
                        ${destinations.size > 0 ? `
                            <p><strong>Destinos asociados:</strong> ${destinations.size}</p>
                            <ul class="tooltip-list">
                                ${Array.from(destinations).map(dest => `<li>${dest}</li>`).join('')}
                            </ul>
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
                if (d.type === "source") return "Servidor";
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
            if (!event.active) simulation.alphaTarget(0.3).restart();
            d.fx = d.x;
            d.fy = d.y;
        }
        
        function dragging(event, d) {
            d.fx = event.x;
            d.fy = event.y;
        }
        
        function dragEnded(event, d) {
            if (!event.active) simulation.alphaTarget(0);
            // Mantener fijo para origen y destino
            if (d.type !== "router") {
                // No resetear fx y fy para mantener la posición
            } else {
                d.fx = null;
                d.fy = null;
            }
        }
        
        // Organizar posiciones iniciales para mejorar la visualización
        // Nodos origen y destino en extremos opuestos
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
        simulation.on("tick", () => {
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
            });
        
        d3svg.call(zoom);
        
        // Ajustar zoom inicial para ver todo el grafo
        const initialScale = 0.9;
        d3svg.call(zoom.transform, d3.zoomIdentity
            .translate(width / 2, height / 2)
            .scale(initialScale)
            .translate(-width / 2, -height / 2));
    }
    
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
            .text("No hay datos disponibles para mostrar");
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
            alert('Por favor, ingrese una dirección IP válida');
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
                alert('Agente añadido correctamente');
                document.getElementById('new-agent-ip').value = '';
                document.getElementById('new-agent-name').value = '';
                await loadAgents();
                loadTopologyData();
            } else {
                alert('Error al añadir agente: ' + (data.error || 'Error desconocido'));
            }
        } catch (error) {
            console.error('Error:', error);
            alert('Error al añadir agente: ' + error.message);
        }
    }
    
    async function scanAgent(address) {
        try {
            const response = await fetch(`/api/scan/${address}`);
            const data = await response.json();
            
            if (data.success) {
                alert(`Agente ${address} escaneado correctamente`);
                loadTopologyData();
            } else {
                alert('Error al escanear agente: ' + (data.error || 'Error desconocido'));
            }
        } catch (error) {
            console.error('Error:', error);
            alert('Error al escanear agente: ' + error.message);
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
                alert(`Agente ${address} ${enable ? 'habilitado' : 'deshabilitado'} correctamente`);
                await loadAgents();
                loadTopologyData();
            } else {
                alert('Error: ' + (data.error || 'Error desconocido'));
            }
        } catch (error) {
            console.error('Error:', error);
            alert('Error: ' + error.message);
        }
    }
    
    async function removeAgent(address) {
        if (!confirm(`¿Está seguro de que desea eliminar el agente ${address}?`)) {
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
                alert(`Agente ${address} eliminado correctamente`);
                await loadAgents();
                loadTopologyData();
            } else {
                alert('Error al eliminar agente: ' + (data.error || 'Error desconocido'));
            }
        } catch (error) {
            console.error('Error:', error);
            alert('Error al eliminar agente: ' + error.message);
        }
    }
    
    async function discoverTelegrafAgents() {
        const path = document.getElementById('telegraf-path').value.trim();
        
        try {
            const response = await fetch(`/api/discover-telegraf?path=${encodeURIComponent(path)}`);
            const data = await response.json();
            
            if (data.success) {
                alert(`Se han descubierto ${data.agents.length} agentes`);
                await loadAgents();
                loadTopologyData();
            } else {
                alert('Error al descubrir agentes: ' + (data.error || 'Error desconocido'));
            }
        } catch (error) {
            console.error('Error:', error);
            alert('Error al descubrir agentes: ' + error.message);
        }
    }
});

