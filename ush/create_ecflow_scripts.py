#!/usr/bin/env python3

import os
import sys
from textwrap import dedent
import jinja2 as j2
from jinja2 import meta
import yaml
import re

from python_utils import (
    import_vars,  
    print_info_msg, 
    print_err_msg_exit,
    cfg_to_yaml_str,
    load_shell_config,
    flatten_dict,
    cp_vrfy,
    mkdir_vrfy
)

from fill_jinja_template import fill_jinja_template

def create_ecflow_scripts(global_var_defns_fp):
    """ Creates ecFlow job cards and definition script in the specific
    experiment directory."""

    cfg = load_shell_config(global_var_defns_fp)
    cfg = flatten_dict(cfg)
    import_vars(dictionary=cfg)

    #
    #-----------------------------------------------------------------------
    #
    # Copy include directory into experiment directory.
    #
    #-----------------------------------------------------------------------
    #
    cp_vrfy("-r", os.path.join(PARMdir,"wflow/ecflow/include"), os.path.join(EXPTDIR, "ecf"))
    #
    #-----------------------------------------------------------------------
    #
    # Create ecFlow job cards and definition script in the experiment directory.
    #
    #-----------------------------------------------------------------------
    #
    print_info_msg(f"""
        Creating ecFlow job cards and definition scripts in the specified 
        experiment directory (EXPTDIR):
          EXPTDIR = '{EXPTDIR}'""", verbose=VERBOSE)
    #
    # Set template file path
    #
    ecflow_script_tmpl_fn = "job_card_template.ecf"
    ecflow_script_tmpl_fp = os.path.join(PARMdir, "wflow/ecflow/job_cards", ecflow_script_tmpl_fn)

    #
    #-----------------------------------------------------------------------
    #
    # Load WFLOW_MANAGE_YAML file (wflow_manage_defns.yaml) into a dictionary
    #
    #-----------------------------------------------------------------------
    #
    with open(WFLOW_MANAGE_YAML_FP, "r") as fn:
        wmgn = yaml.load(fn, Loader=yaml.SafeLoader)

    #
    #-----------------------------------------------------------------------
    #
    # Set up task groups from configuration yaml files
    #
    #-----------------------------------------------------------------------
    #
    task_group_str = wmgn["tasks"]["taskgroups"]
    task_group_ini = re.findall('"([^"]*)"', task_group_str)
    task_group_srt = [ tsk.replace('parm/',"") for tsk in task_group_ini ]
    task_group_orgi = {}
    task_group = {}
    task_all = []
    for tgrp in task_group_srt:
        tgrp_key = tgrp.replace('wflow/',"").replace('.yaml',"")
        task_group_fp = os.path.join(PARMdir,tgrp)
        with open(task_group_fp, "r") as fn:
            tgrp_data = yaml.load(fn, Loader=yaml.SafeLoader)
        tgrp_list_raw = list(tgrp_data.keys())
        if CPL_AQM and COLDSTART:
            if "task_aqm_ics_ext" in tgrp_list_raw:
                tgrp_list_raw.remove("task_aqm_ics_ext")
        tgrp_single_orgi = [ tsk for tsk in tgrp_list_raw if tsk.startswith('task_') ]
        tgrp_single = [ tsk.replace('task_',"") for tsk in tgrp_single_orgi ]
        tgrp_meta_orgi = [ tsk for tsk in tgrp_list_raw if tsk.startswith('metatask_') ]
        tgrp_meta = [ tsk.replace('metatask_',"") for tsk in tgrp_meta_orgi ]
        if "run_ensemble" in tgrp_meta:
            tgrp_meta.remove('run_ensemble')
            tgrp_ensemble_raw = list(tgrp_data["metatask_run_ensemble"].keys())
            tgrp_ensemble_orgi = [ tsk.replace('task_','enstask_') for tsk in tgrp_ensemble_raw if tsk.startswith('task_') ]
            tgrp_ensemble = [ tsk.replace('enstask_',"").replace('_mem#mem#',"") for tsk in tgrp_ensemble_orgi ]
            if len(tgrp_meta) == 0:
                tgrp_orgi_value = tgrp_single_orgi + tgrp_ensemble_orgi
                tgrp_value = tgrp_single + tgrp_ensemble
            else:
                tgrp_orgi_value = tgrp_single_orgi + tgrp_meta_orgi + tgrp_ensemble_orgi
                tgrp_value = tgrp_single + tgrp_meta + tgrp_ensemble
        else:
            tgrp_orgi_value = tgrp_single_orgi + tgrp_meta_orgi
            tgrp_value = tgrp_single + tgrp_meta

        task_group_orgi[tgrp_key] = tgrp_orgi_value
        task_group[tgrp_key] = tgrp_value
        task_all.extend(tgrp_orgi_value)

    #
    #-----------------------------------------------------------------------
    #
    # Create group directories for job cards
    #
    #-----------------------------------------------------------------------
    #
    for tgrp in list(task_group.keys()):
        mkdir_vrfy("-p", os.path.join(EXPTDIR,"ecf/scripts",tgrp))
    #
    #-----------------------------------------------------------------------
    #
    # Create job cards for tasks
    #
    #-----------------------------------------------------------------------
    #
    for tsk in task_all:
        print_info_msg(f"""Creating ecFlow job card for '{tsk}'...""")
        wmgn_task = {}
        if tsk.startswith('task_'):
            # tast names of top level (n0), first (n1) and second (n2) nests
            task_name_n0 = tsk.replace('task_',"")
            task_name_n1 = task_name_n0
            task_name_n2 = task_name_n0
            wmgn_task = wmgn["tasks"][tsk]
        elif tsk.startswith('metatask_'):
            task_name_n0 = tsk.replace('metatask_',"")
            if task_name_n0 == "run_ens_post":
                task_name_n1_orgi = list(wmgn["tasks"][tsk].keys())[1]
                task_name_n1 = task_name_n1_orgi.replace('metatask_',"")
                task_name_n2_orgi = list(wmgn["tasks"][tsk][task_name_n1_orgi].keys())[1]
                task_name_n2 = task_name_n2_orgi.replace('task_',"").replace('#','%')
                wmgn_task = wmgn["tasks"][tsk][task_name_n1_orgi][task_name_n2_orgi]
            else:
                task_name_n1 = task_name_n0
                task_name_n2_orgi = list(wmgn["tasks"][tsk].keys())[1]
                task_name_n2 = task_name_n2_orgi.replace('task_',"").replace('#','%')
                wmgn_task = wmgn["tasks"][tsk][task_name_n2_orgi]
        elif tsk.startswith('enstask_'):
            task_name_n0 = "metatask_run_ensemble"
            task_name_n1_orig = tsk.replace('enstask_','task_')
            task_name_n1 = tsk.replace('enstask_',"").replace('_mem#mem#',"")
            task_name_n2 = tsk.replace('enstask_',"").replace('#','%')
            wmgn_task = wmgn["tasks"][task_name_n0][task_name_n1_orig]

        task_nnodes = wmgn_task["nnodes"]
        task_ppn = wmgn_task["ppn"]
        task_walltime = wmgn_task["walltime"]
        if "memory" in list(wmgn_task.keys()):
            task_memory = wmgn_task["memory"]
        else:
            task_memory = "2G"

        tsk_grp = [key for key, val in task_group_orgi.items() if tsk in val][0]
        ecflow_script_fn = f"j{task_name_n1}.ecf"
        ecflow_script_fp = os.path.join(EXPTDIR, "ecf/scripts", tsk_grp, ecflow_script_fn)

        task_omp_vn = f"OMP_NUM_THREADS_{task_name_n1.upper()}"
        if task_omp_vn in cfg:
            task_omp = cfg[task_omp_vn]
        else:
            task_omp = "1"

        task_ncpus = str(int(task_omp)*int(task_ppn))
        task_select = f"select={task_nnodes}:mpiprocs={task_ppn}:ompthreads={task_omp}:ncpus={task_ncpus}"
       
        settings = {
          "ecf_task_name_n1": task_name_n1,
          "ecf_task_name_n2": task_name_n2,
          "ecf_task_walltime": task_walltime,
          "ecf_task_select": task_select,
          "ecf_task_memory": task_memory,
          "sched_native_cmd": SCHED_NATIVE_CMD,
          "exptdir": EXPTDIR,
        }
        settings_str = cfg_to_yaml_str(settings)
            
        # Call a python script to generate the ecFlow job card.
        args = ["-q",
                "-o", ecflow_script_fp,
                "-t", ecflow_script_tmpl_fp,
                "-u", settings_str ]

        try:
            fill_jinja_template(args)
        except:
            raise Exception(
                dedent(
                f"""Call to create the ecFlow job card for '{task_name}' failed."""
                )
            )

    return True


if __name__ == "__main__":
    create_ecflow_scripts(global_var_defns_fp)
