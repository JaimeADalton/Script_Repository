import tkinter as tk
from tkinter import ttk, messagebox
import matplotlib.pyplot as plt
from matplotlib.backends.backend_tkagg import FigureCanvasTkAgg
import subprocess
import threading
import time
import csv
from datetime import datetime
from collections import deque

class NetworkMonitor:
    def __init__(self, master):
        self.master = master
        self.master.title("Monitor de Red")
        self.master.geometry("1000x700")
        self.master.configure(bg='#f0f0f0')

        self.devices = {}
        self.running = False
        self.max_data_points = 100

        self.create_widgets()

    def create_widgets(self):
        # Frame principal
        main_frame = ttk.Frame(self.master, padding="20")
        main_frame.pack(fill=tk.BOTH, expand=True)

        # Frame de entrada
        input_frame = ttk.Frame(main_frame, padding="10")
        input_frame.pack(fill=tk.X, pady=(0, 20))

        ttk.Label(input_frame, text="Dirección IP:").pack(side=tk.LEFT)
        self.ip_entry = ttk.Entry(input_frame, width=30)
        self.ip_entry.pack(side=tk.LEFT, expand=True, fill=tk.X, padx=5)

        ttk.Button(input_frame, text="Añadir", command=self.add_device).pack(side=tk.LEFT, padx=(0, 5))
        self.start_button = ttk.Button(input_frame, text="Iniciar", command=self.start_monitoring)
        self.start_button.pack(side=tk.LEFT, padx=(0, 5))
        self.stop_button = ttk.Button(input_frame, text="Detener", command=self.stop_monitoring, state=tk.DISABLED)
        self.stop_button.pack(side=tk.LEFT)

        # Frame de dispositivos
        device_frame = ttk.Frame(main_frame, padding="10")
        device_frame.pack(fill=tk.BOTH, expand=True)

        self.device_tree = ttk.Treeview(device_frame, columns=('IP', 'Status'), show='headings')
        self.device_tree.heading('IP', text='Dirección IP')
        self.device_tree.heading('Status', text='Estado')
        self.device_tree.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)

        scrollbar = ttk.Scrollbar(device_frame, orient=tk.VERTICAL, command=self.device_tree.yview)
        scrollbar.pack(side=tk.RIGHT, fill=tk.Y)
        self.device_tree.configure(yscrollcommand=scrollbar.set)

        # Frame del gráfico
        graph_frame = ttk.Frame(main_frame, padding="10")
        graph_frame.pack(fill=tk.BOTH, expand=True)

        self.fig, self.ax = plt.subplots(figsize=(10, 4), dpi=100)
        self.canvas = FigureCanvasTkAgg(self.fig, master=graph_frame)
        self.canvas.draw()
        self.canvas.get_tk_widget().pack(fill=tk.BOTH, expand=True)

    def add_device(self):
        ip = self.ip_entry.get().strip()
        if ip and ip not in self.devices:
            self.devices[ip] = {
                "latency": deque(maxlen=self.max_data_points),
                "status": "No iniciado",
                "tree_id": self.device_tree.insert('', 'end', values=(ip, "No iniciado"))
            }
            self.ip_entry.delete(0, tk.END)
        elif ip in self.devices:
            messagebox.showwarning("Advertencia", f"La IP {ip} ya está en la lista.")
        else:
            messagebox.showwarning("Advertencia", "Por favor, ingrese una dirección IP válida.")

    def start_monitoring(self):
        self.running = True
        self.start_button.config(state=tk.DISABLED)
        self.stop_button.config(state=tk.NORMAL)
        for ip in self.devices:
            threading.Thread(target=self.monitor_device, args=(ip,), daemon=True).start()

    def stop_monitoring(self):
        self.running = False
        self.start_button.config(state=tk.NORMAL)
        self.stop_button.config(state=tk.DISABLED)

    def monitor_device(self, ip):
        while self.running:
            try:
                output = subprocess.check_output(["ping", "-c", "1", ip], universal_newlines=True)
                latency = float(output.split("time=")[1].split()[0])
                self.devices[ip]["latency"].append(latency)
                status = f"Latencia: {latency:.2f} ms"
                self.devices[ip]["status"] = status
                self.log_event(ip, latency, "Éxito")
            except subprocess.CalledProcessError:
                self.devices[ip]["latency"].append(None)
                status = "Inalcanzable"
                self.devices[ip]["status"] = status
                self.log_event(ip, None, "Fallo")
            except Exception as e:
                print(f"Error al hacer ping a {ip}: {str(e)}")
                self.devices[ip]["latency"].append(None)
                status = "Error"
                self.devices[ip]["status"] = status
                self.log_event(ip, None, "Error")

            self.master.after(0, self.update_device_status, ip, status)
            self.master.after(0, self.update_graph)
            time.sleep(1)

    def update_device_status(self, ip, status):
        self.device_tree.item(self.devices[ip]["tree_id"], values=(ip, status))

    def update_graph(self):
        try:
            self.ax.clear()
            for ip, data in self.devices.items():
                latencies = [l for l in data["latency"] if l is not None]
                if latencies:
                    self.ax.plot(latencies, label=ip)
            self.ax.legend()
            self.ax.set_xlabel("Tiempo")
            self.ax.set_ylabel("Latencia (ms)")
            self.ax.set_title("Monitoreo de Latencia")
            self.canvas.draw()
        except Exception as e:
            print(f"Error al actualizar el gráfico: {str(e)}")

    def log_event(self, ip, latency, status):
        with open("network_log.csv", "a", newline="") as csvfile:
            writer = csv.writer(csvfile)
            writer.writerow([datetime.now(), ip, latency, status])

if __name__ == "__main__":
    root = tk.Tk()
    app = NetworkMonitor(root)
    root.mainloop()
