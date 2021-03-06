#!/bin/bash
################################################################################
#    Copyright (c) Microsoft. All rights reserved.
#    
#    Apache 2.0 License
#    
#    You may obtain a copy of the License at
#    http://www.apache.org/licenses/LICENSE-2.0
#    
#    Unless required by applicable law or agreed to in writing, software 
#    distributed under the License is distributed on an "AS IS" BASIS, 
#    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or 
#    implied. See the License for the specific language governing 
#    permissions and limitations under the License.
#
################################################################################
prev_dir=${pwd}
notebook_dir="${HOME}/ipython_notebooks"

UpdateSystem()
{
    echo "Updating Apt and Packages"
    sudo apt-get -y update
    sudo apt-get -y install curl
    # Super needed to run setuid on system startup of IPython
    sudo apt-get install super
}

DownloadRawFromGitWithFileList()
{   
    base_url=$1
    file_list_name=$2
    destination_dir=$3

    mkdir $destination_dir
    cd $destination_dir

    # Download the list so we can iterate over it.
    url="${base_url}${file_list_name}"
    curl -O $url

    echo "" >> $file_list_name # on a single line file it seems to miss the last line

    echo "Downloading Files..."
    while read curLine
    do 
        if [ ! -z "$curLine" ]; then
            # URL Encode line from file using python.
            encoded_curLine=$(python -c "import urllib; print urllib.quote('$curLine')")
            url="${base_url}${encoded_curLine}"
            echo $url

            curl -O "${url}"
        fi
    done < $file_list_name

    # remove list since we don't need it.
    rm $file_list_name
}

GetSampleNotebooksFromGit()
{
    base_url="https://raw.githubusercontent.com/Azure/Azure-MachineLearning-DataScience/master/Misc/DataScienceProcess/iPythonNotebooks/"
    notebook_list_name="Notebook_List.txt"
    destination_dir="${notebook_dir}/AzureMLSamples"

    mkdir $notebook_dir
    DownloadRawFromGitWithFileList $base_url $notebook_list_name $destination_dir
}

InstallAnacondaAndPythonDependencies()
{
    #Install Anaconda but only if Anaconda isn't installed already.
    if [[ ! -d $HOME/anaconda ]]; then
        # Install Anaconda
        mkdir -p $HOME/anaconda
        cd $HOME/anaconda;curl -O http://09c8d0b2229f813c1b93-c95ac804525aac4b6dba79b00b39d1d3.r79.cf1.rackcdn.com/Anaconda-2.1.0-Linux-x86_64.sh
        cd $HOME/anaconda;sudo bash Anaconda-2.1.0-Linux-x86_64.sh -b -f -p /anaconda
        sudo /anaconda/bin/conda update -f ipython --yes
        sudo /anaconda/bin/conda update -f pandas --yes
    fi
    
    # Install Azure and AzureML API SDKs
    sudo apt-get -y install python-pip

    # Update the packages on every run (just in case they have changed since the user first ran this script)
    sudo pip install -U --install-option="--prefix=/anaconda/" azure
    sudo pip install -U --install-option="--prefix=/anaconda/" azureml

    sudo apt-get -y install python-dev
    sudo apt-get -y install unixodbc-dev
    sudo pip install -U --install-option="--prefix=/anaconda/" https://pyodbc.googlecode.com/files/pyodbc-3.0.7.zip
}

SetupIPythonNotebookService()
{ 
    # Configure IPython notebook, but only if the .ipython/profile_nbserver directory isn't already there.
    # if you need to generate this again, the easiest thing to do is 'rm -rf ~/.ipython/profile_nbserver'
    if [[ ! -d $HOME/.ipython/profile_nbserver ]]; then
        /anaconda/bin/ipython profile create nbserver
        cd ~/.ipython/profile_nbserver
        openssl req -x509 -nodes -days 365 -newkey rsa:1024 -keyout mycert.pem -out mycert.pem -subj "/C=US/ST=WA/L=Redmond/O=IT/CN=cloudapp.net"

        mkdir $notebook_dir

        # Set Password to IPython Notebook
        echo "We require a password on your IPython Notebook Service.  Please Enter it Below..."
        /anaconda/bin/python -c 'import IPython;print IPython.lib.passwd()' | tee passwordfile.txt
        x=( $( cat passwordfile.txt ) )
        passwordHash=${x[-1]}
        rm passwordfile.txt

        # Append our custom settings to the end of the notebook config.  Last setting will win so ours will override.
        filelines=( "c = get_config()" \
                    "# This starts plotting support always with matplotlib" \
                    "c.IPKernelApp.pylab = 'inline'" \
                    "" \
                    "# You must give the path to the certificate file." \
                    "" \
                    "# If using a Linux VM (Ubuntu):" \
                    "c.NotebookApp.certfile = u'${HOME}/.ipython/profile_nbserver/mycert.pem'" \
                    "" \
                    "# Create your own password as indicated above" \
                    "c.NotebookApp.password = u'${passwordHash}'" \
                    "" \
                    "# Network and browser details. We use a fixed port (9999) so it matches" \
                    "# our Azure setup  where we've allowed traffic on that port" \
                    "" \
                    "c.NotebookApp.ip = '*'" \
                    "c.NotebookApp.port = 9999" \
                    "c.NotebookApp.open_browser = False" \
                    "c.FileNotebookManager.notebook_dir = u'${notebook_dir}'")

        for i in "${filelines[@]}"
        do 
            echo $i >> ~/.ipython/profile_nbserver/ipython_notebook_config.py
        done
    fi
}

StartIPythonNotebookService()
{
    echo "cd ${HOME};setuid ${USER} nohup /anaconda/bin/ipython notebook --profile=nbserver > t.log 2>&1 < /dev/null &" > start_ipython
    sudo mv start_ipython /etc/init.d/start_ipython
    sudo chmod +x /etc/init.d/start_ipython 
    sudo update-rc.d start_ipython defaults

    # Notes: 
    # To kill the process (if something goes wrong) use 'pkill nohup;pkill ipython'
    # If you run just '/anaconda/bin/ipython notebook --profile=nbserver' you will be able
    # to see the failure causes.  You can also 'cat t.log'
    # If you want to stop this script from running at startup, run: sudo update-rc.d -f start_ipython remove
    echo "Starting the IPython Notebook Service"
    cd /etc/init.d
    sudo ./start_ipython
}

###################### End of Functions / Start of Script ######################
echo "This script has been tested against the Azure Virtual Machine Image for Ubuntu 14.10, 14.04 LTS, and 12.04 LTS"
echo "Other OS Versions may work but are not officially supported."

UpdateSystem
InstallAnacondaAndPythonDependencies
GetSampleNotebooksFromGit
SetupIPythonNotebookService # Make sure this is last in the script as this start IPython Notebook Service
StartIPythonNotebookService

# Log that this script was run so we have usage numbers.
curl -o /dev/null "http://pageviews.azurewebsites.net/pageview?Azure_VM_Setup_Ubuntu.sh"

cd $prev_dir