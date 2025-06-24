#!/usr/bin/env python3
"""
master_network_analyzer_v10.py – Script con Estimación de Tiempo Holística y Precisa
-----------------------------------------------------------------------------------------
Esta versión final perfecciona la estimación de tiempo para que sea verdaderamente precisa.

MEJORAS CLAVE:
1. ESTIMACIÓN HOLÍSTICA: El tiempo total estimado ahora es la suma del tiempo de sondeo
   Y el tiempo de post-procesamiento (análisis, gráficos, guardado), ofreciendo la
   predicción más realista posible.
2. HEURÍSTICA DE PROCESAMIENTO: Se introduce una constante (`PROCESSING_TIME_PER_HOST`) para
   estimar de forma robusta la fase de análisis.
3. MANTIENE todas las mejoras de usabilidad, robustez y etiquetado inteligente de versiones anteriores.
"""

import os
import sys
import json
import subprocess
import threading
import time
import math
from concurrent.futures import ThreadPoolExecutor, as_completed

# Librerías de análisis y visualización
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import seaborn as sns
from sklearn.preprocessing import StandardScaler
from sklearn.decomposition import PCA
from sklearn.cluster import KMeans
from adjustText import adjust_text
from tqdm import tqdm

# --- Configuración ---
URLS = [
    "google.com", "cloudflare.com", "github.com",
    "openai.com", "wikipedia.org", "amazon.com", "facebook.com",
    "microsoft.com", "youtube.com", "reddit.com", "stackoverflow.com",
    "netflix.com", "zoom.us", "dropbox.com", "oracle.com",
    "debian.org", "akamai.com", "level3.net", "telia.net"
]
EXECUTION_TIME = "1m"
INTERVAL = 0.5
OUTDIR   = "master_mtr_analysis_final"
N_CLUSTERS = 3

# --- Heurística de Procesamiento ---
# Segundos estimados que tarda el análisis y la generación de gráficos por cada host.
# Ajusta este valor si tu máquina es significativamente más rápida o lenta.
PROCESSING_TIME_PER_HOST = 1.5

# Ejecución totalmente paralela
WORKERS = len(URLS)

os.makedirs(OUTDIR, exist_ok=True)
plt.style.use('seaborn-v0_8-whitegrid')

# --- Utilidades, Captura y Parseo (Sin cambios) ---
def parse_duration(duration_str: str) -> int:
    duration_str=duration_str.strip().lower();multipliers={'s':1,'m':60,'h':3600,'d':86400};unit=duration_str[-1]
    if unit in multipliers:
        try:return int(float(duration_str[:-1])*multipliers[unit])
        except ValueError:raise ValueError(f"Valor de duración inválido: '{duration_str}'")
    else:
        try:return int(float(duration_str))
        except ValueError:raise ValueError(f"Formato de duración no reconocido: '{duration_str}'")
def get_interval(desired:float)->float:
    if os.geteuid()!=0 and desired<0.2:
        if not hasattr(get_interval,'warned'):print(f"⚠️ No-root: Intervalo ajustado de {desired}s a 0.2s.");get_interval.warned=True
        return 0.2
    return desired
def grab(h:dict,*keys,default=None):
    for k in keys:
        if k in h:return h[k]
        lk=k.lower()
        if lk in h:return h[lk]
    val=default;
    if val is None:return None
    try:return float(val)
    except(ValueError,TypeError):return val
def serialize_analysis_dict(analysis_data:dict)->dict:
    serializable={};
    for key,value in analysis_data.items():
        if isinstance(value,pd.DataFrame):serializable[key]=value.to_dict(orient='split')
        elif isinstance(value,pd.Series):serializable[key]=value.to_dict()
        elif isinstance(value,np.ndarray):serializable[key]=value.tolist()
        elif isinstance(value,(np.generic)):serializable[key]=value.item()
        elif isinstance(value,dict):serializable[key]=serialize_analysis_dict(value)
        else:serializable[key]=value
    return serializable
def probe(host:str,rounds:int,interval:float):
    cmd=["mtr","--json","-c",str(rounds),"-i",str(interval),host]
    proc=subprocess.run(cmd,capture_output=True,text=True,check=False)
    if proc.returncode!=0:
        if"resolve"not in proc.stderr.lower():tqdm.write(f"\n⚠️ Error en {host}: {proc.stderr.strip()}")
        return host,None
    try:return host,json.loads(proc.stdout)
    except json.JSONDecodeError:tqdm.write(f"\n⚠️ JSON inválido en {host}.");return host,None
def parse_df_realistic(data:dict)->pd.DataFrame:
    hubs=data.get("report",{}).get("hubs",[]);rows=[]
    for h in hubs:
        row={"hop":grab(h,"count","hop"),"host":grab(h,"host",default="???"),"loss":grab(h,"Loss%","loss"),"avg":grab(h,"Avg","avg"),"stdev":grab(h,"StDev","stdev"),"best":grab(h,"Best","best"),"worst":grab(h,"Wrst","worst")}
        for key in["hop","loss","avg","stdev","best","worst"]:
            if row[key] is not None:row[key]=float(row[key])
            else:row[key]=0.0
        row["cv"]=row["stdev"]/row["avg"]if row["avg"]and row["avg"]>0 else 0.0
        rows.append(row)
    return pd.DataFrame(rows).sort_values("hop").reset_index(drop=True)

# --- Análisis Matemático y Estadístico (Sin cambios) ---
def perform_comprehensive_analysis(all_data_dfs:dict):
    analysis={};summary_list=[]
    for host,df in all_data_dfs.items():
        if df.empty:continue
        last_hop=df[df['loss']<100].iloc[-1]if not df[df['loss']<100].empty else df.iloc[-1]
        summary_list.append({'Host':host,'Latency (ms)':last_hop['avg'],'Std Dev (ms)':last_hop['stdev'],'Packet Loss (%)':last_hop['loss'],'Stability (CV)':last_hop['cv']})
    summary_df=pd.DataFrame(summary_list).set_index('Host').dropna()
    analysis['summary_df']=summary_df
    if not summary_df.empty and len(summary_df)>=N_CLUSTERS:
        summ_numeric=summary_df.select_dtypes(include=np.number)
        scaler=StandardScaler();scaled_features=scaler.fit_transform(summ_numeric)
        kmeans=KMeans(n_clusters=N_CLUSTERS,random_state=42,n_init='auto')
        clusters_raw=kmeans.fit_predict(scaled_features);summary_df['cluster_raw']=clusters_raw
        cluster_means=summary_df.groupby('cluster_raw').mean()
        normalized_means=(cluster_means-cluster_means.mean())/cluster_means.std()
        dominant_feature=normalized_means[['Latency (ms)','Std Dev (ms)','Packet Loss (%)']].idxmax(axis=1)
        feature_map={'Latency (ms)':"Latencia Alta",'Std Dev (ms)':"Inestable",'Packet Loss (%)':"Pérdida Paquetes"}
        cluster_centers_dist=np.linalg.norm(kmeans.cluster_centers_,axis=1)
        best_cluster_id=np.argmin(cluster_centers_dist)
        cluster_labels={}
        for i,feature in dominant_feature.items():
            if i==best_cluster_id:cluster_labels[i]="Rendimiento Óptimo"
            else:cluster_labels[i]=f"Perfil: {feature_map.get(feature,'Atípico')}"
        analysis['clusters']=summary_df['cluster_raw'].map(cluster_labels)
        analysis['clusters'].name="Performance Profile"
    bottlenecks={};
    for host,df in all_data_dfs.items():
        if df.shape[0]<2:continue
        df['latency_delta']=df['avg'].diff()
        idx_lat=df['latency_delta'].idxmax()
        if pd.notna(idx_lat)and df.loc[idx_lat,'latency_delta']>0:bottlenecks[host]={'hop':int(df.loc[idx_lat,'hop']),'host_name':df.loc[idx_lat,'host'],'latency_increase':df.loc[idx_lat,'latency_delta']}
    analysis['bottlenecks']=bottlenecks
    summ_variant=summ_numeric.loc[:,summ_numeric.nunique()>1]
    analysis['correlation_matrix']=summ_variant.corr()
    if not summary_df.empty:
        pca=PCA(n_components=2);principal_components=pca.fit_transform(scaled_features)
        analysis['pca']={'components':pd.DataFrame(data=principal_components,columns=['PC1','PC2'],index=summary_df.index),'explained_variance':pca.explained_variance_ratio_}
    return analysis

# --- Visualizaciones (Sin cambios) ---
def plot_performance_overview(analysis:dict,outdir:str):
    summary_df=analysis.get('summary_df');
    if summary_df is None or summary_df.empty:return
    fig,axes=plt.subplots(2,2,figsize=(20,14));fig.suptitle('Visión General del Rendimiento de Red',fontsize=20,fontweight='bold')
    plot_configs={'Latency (ms)':{'ax':axes[0,0],'color':'royalblue','title':'Latencia Media al Destino'},'Std Dev (ms)':{'ax':axes[0,1],'color':'orange','title':'Inestabilidad (Desviación Estándar)'},'Packet Loss (%)':{'ax':axes[1,0],'color':'crimson','title':'Pérdida de Paquetes'},'Stability (CV)':{'ax':axes[1,1],'color':'forestgreen','title':'Estabilidad Relativa (Coef. de Variación)'}}
    for metric,config in plot_configs.items():
        ax=config['ax'];data_to_plot=summary_df[metric].sort_values()
        data_to_plot.plot(kind='bar',ax=ax,color=config['color'],alpha=0.8)
        ax.set_title(config['title'],fontsize=14);ax.set_ylabel(metric);ax.set_xlabel('')
        ax.set_xticklabels(data_to_plot.index,rotation=45,ha='right')
    plt.tight_layout(rect=[0,0.03,1,0.95]);plt.savefig(f"{outdir}/00_performance_overview.png",dpi=300);plt.close(fig)
def plot_correlation_and_clustering(analysis:dict,outdir:str):
    if'correlation_matrix'not in analysis or'pca'not in analysis:return
    fig,axes=plt.subplots(1,2,figsize=(22,10));fig.suptitle('Análisis de Relaciones y Agrupamiento',fontsize=20,fontweight='bold')
    ax=axes[0];sns.heatmap(analysis['correlation_matrix'],annot=True,cmap='vlag',fmt=".2f",linewidths=.5,ax=ax);ax.set_title('Correlación entre Métricas',fontsize=14)
    ax=axes[1];pca_df=analysis['pca']['components'].copy();pca_df['cluster']=analysis['clusters']
    palette="viridis"
    sns.scatterplot(data=pca_df,x='PC1',y='PC2',hue='cluster',palette=palette,s=120,alpha=0.9,ax=ax)
    texts=[ax.text(row['PC1'],row['PC2'],idx,fontsize=9)for idx,row in pca_df.iterrows()]
    adjust_text(texts,arrowprops=dict(arrowstyle='->',color='gray',lw=0.5))
    exp_var=analysis['pca']['explained_variance']
    ax.set_xlabel(f"Componente Principal 1 ({exp_var[0]:.1%})",fontsize=12)
    ax.set_ylabel(f"Componente Principal 2 ({exp_var[1]:.1%})",fontsize=12)
    ax.set_title('Agrupación de Hosts por Perfil de Red',fontsize=14);ax.legend(title='Perfil de Rendimiento');ax.grid(True)
    plt.tight_layout(rect=[0,0.03,1,0.95]);plt.savefig(f"{outdir}/01_correlation_and_clustering.png",dpi=300);plt.close(fig)
def plot_bottlenecks(analysis:dict,outdir:str):
    bottlenecks=analysis.get('bottlenecks',{});
    if not bottlenecks:return
    data=pd.DataFrame.from_dict(bottlenecks,orient='index').sort_values('latency_increase',ascending=False)
    data=data[data['latency_increase']>5]
    if data.empty:return
    fig,ax=plt.subplots(figsize=(15,8));norm=plt.Normalize(data['latency_increase'].min(),data['latency_increase'].max())
    colors=plt.colormaps.get_cmap('Reds')(norm(data['latency_increase']));ax.bar(data.index,data['latency_increase'],color=colors)
    ax.set_xticks(range(len(data.index)));ax.set_xticklabels(data.index,rotation=45,ha='right',fontsize=10)
    ax.set_ylabel('Aumento de Latencia (ms)');ax.set_title('Detección de Cuellos de Botella',fontsize=16)
    for i,(idx,row)in enumerate(data.iterrows()):
        ax.text(i,row['latency_increase']+1,f" H{row['hop']:.0f}\n {row['host_name']}",ha='center',va='bottom',fontsize=8,rotation=90)
    fig.tight_layout();plt.savefig(f"{outdir}/02_bottleneck_analysis.png",dpi=300);plt.close(fig)
def plot_per_host_details(host:str,df:pd.DataFrame,outdir:str):
    if df.empty:return
    fig,axes=plt.subplots(1,2,figsize=(15,6));fig.suptitle(f'Análisis Detallado para: {host}',fontsize=16,fontweight='bold')
    ax=axes[0];ax.plot(df['hop'],df['avg'],'o-',label='Latencia Media',color='b');ax.fill_between(df['hop'],df['best'],df['worst'],color='b',alpha=0.2,label='Rango (Best-Worst)')
    ax.set_ylabel('Latencia (ms)');ax.set_xlabel('Salto');ax.set_title('Latencia y Rango por Salto');ax.legend();ax.grid(True)
    ax=axes[1];ax.bar(df['hop'],df['loss'],color='red',alpha=0.7)
    ax.set_xlabel('Salto');ax.set_ylabel('Pérdida de Paquetes (%)');ax.set_title('Pérdida de Paquetes por Salto');ax.axhline(5,color='orange',linestyle='--',lw=1);ax.grid(True)
    plt.tight_layout(rect=[0,0.03,1,0.95]);plt.savefig(f"{outdir}/{host}_details.png",dpi=300);plt.close(fig)

# --- Main ---
def main():
    try: single_test_duration = parse_duration(EXECUTION_TIME)
    except ValueError as e: print(f"Error: {e}"); sys.exit(1)

    actual_interval = get_interval(INTERVAL)
    calculated_rounds = max(10, int(single_test_duration / actual_interval))

    # --- ESTIMACIÓN DE TIEMPO HOLÍSTICA ---
    probing_time = single_test_duration + 5 # 5 segundos de margen
    processing_time = len(URLS) * PROCESSING_TIME_PER_HOST
    estimated_total_seconds = int(probing_time + processing_time)

    print("="*50 + "\n      Configuración del Análisis de Red\n" + "="*50)
    print(f"Duración de prueba por host:   {EXECUTION_TIME} (~{single_test_duration} s)")
    print(f"Intervalo real entre pings:      {actual_interval} s")
    print(f"Ciclos a realizar por host:      {calculated_rounds}")
    print(f"Workers paralelos (simultáneos): {WORKERS} (de {len(URLS)} hosts)")
    print("-" * 50)
    print(f"Tiempo de sondeo estimado:       ~{probing_time // 60}m {probing_time % 60}s")
    print(f"Tiempo de procesamiento est.:    ~{int(processing_time)}s")
    print(f"TIEMPO TOTAL ESTIMADO (APROX):   ~{estimated_total_seconds // 60}m {estimated_total_seconds % 60}s")
    print("="*50)

    all_data_dfs={}
    stop_progress_thread=threading.Event()
    def time_progress(pbar):
        while not stop_progress_thread.is_set():
            time.sleep(1);pbar.update(1)
            if pbar.n>=pbar.total:break

    with tqdm(total=int(probing_time),desc="🌐 Sondeando redes (simultáneo)",unit="s",bar_format="{l_bar}{bar}| {n_fmt}/{total_fmt}s [{elapsed}<{remaining}]")as pbar_time:
        progress_thread=threading.Thread(target=time_progress,args=(pbar_time,))
        progress_thread.start()
        with ThreadPoolExecutor(max_workers=WORKERS)as executor:
            future_to_host={executor.submit(probe,host,calculated_rounds,actual_interval):host for host in URLS}
            for future in as_completed(future_to_host):
                host=future_to_host[future]
                try:
                    _,data=future.result()
                    if data:df=parse_df_realistic(data);all_data_dfs[host]=df
                except Exception as e:tqdm.write(f"\nError procesando {host}: {e}")
        stop_progress_thread.set();progress_thread.join()
        if pbar_time.n<pbar_time.total:pbar_time.update(pbar_time.total-pbar_time.n)

    if not all_data_dfs:print("\n❌ No se pudo obtener datos. Saliendo.");sys.exit(1)

    analysis_tasks=["Realizando análisis y etiquetado","Generando dashboard de rendimiento","Generando gráfico de correlación/clusters","Generando gráfico de cuellos de botella","Generando informes detallados","Guardando resultados en ficheros"]
    with tqdm(total=len(analysis_tasks),desc="⚙️  Procesando resultados")as pbar_tasks:
        pbar_tasks.set_description(analysis_tasks.pop(0));analysis=perform_comprehensive_analysis(all_data_dfs);pbar_tasks.update(1)
        pbar_tasks.set_description(analysis_tasks.pop(0));plot_performance_overview(analysis,OUTDIR);pbar_tasks.update(1)
        pbar_tasks.set_description(analysis_tasks.pop(0));plot_correlation_and_clustering(analysis,OUTDIR);pbar_tasks.update(1)
        pbar_tasks.set_description(analysis_tasks.pop(0));plot_bottlenecks(analysis,OUTDIR);pbar_tasks.update(1)
        pbar_tasks.set_description(analysis_tasks.pop(0))
        for host,df in all_data_dfs.items():plot_per_host_details(host,df,OUTDIR)
        pbar_tasks.update(1)
        pbar_tasks.set_description(analysis_tasks.pop(0))
        for host,df in all_data_dfs.items():df.to_csv(f"{OUTDIR}/{host}.csv",index=False)
        serializable_analysis=serialize_analysis_dict(analysis)
        with open(f"{OUTDIR}/00_full_analysis_data.json",'w')as f:json.dump(serializable_analysis,f,indent=2)
        pbar_tasks.update(1)

    print("\n"+"="*25+" RESUMEN DEL ANÁLISIS "+"="*25)
    print(analysis['summary_df'][['Latency (ms)','Std Dev (ms)','Packet Loss (%)','Stability (CV)']].round(2))
    print("\n"+"="*20+" Perfiles de Rendimiento "+"="*20)
    if 'clusters' in analysis:
        print(analysis['clusters'])
    else:
        print("No se pudieron generar perfiles (datos insuficientes).")
    print(f"\n✅ Análisis completo. Resultados guardados en '{OUTDIR}'.")

if __name__ == '__main__':
    main()
