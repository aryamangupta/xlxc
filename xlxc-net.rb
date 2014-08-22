#
# xlxc-net: create a Linux XIA container network
#
# Author: Cody Doucette <doucette@bu.edu>
#
# This Ruby script batches the creation of Linux XIA containers
# so that more intricate networks can be quickly created.
#

 
require 'optparse'
require './xlxc'
require './xlxc-bridge'


USAGE =
  "\nUsage:"                                                 \
  "\truby xlxc-net.rb -n name -s size -t topology -i iface"  \
  "\n\tOR\n"                                                 \
  "\truby xlxc-net.rb -n name -s size -t topology --del\n\n"

# Parse the command and organize the options.
#
def parse_opts()
  options = {}

  optparse = OptionParser.new do |opts|
    opts.banner = USAGE

    options[:delete] = false
    opts.on('-d', '--delete', 'Delete this container network') do
      options[:delete] = true
    end

    options[:iface] = nil
    opts.on('-i', '--iface ARG', 'Host gateway interface') do |iface|
      options[:iface] = iface
    end

    options[:name] = nil
    opts.on('-n', '--name ARG', 'Network naming scheme') do |name|
      options[:name] = name
    end

    options[:size] = 0
    opts.on('-s', '--size ARG', 'Size of network') do |size|
      options[:size] = size.to_i()
    end

    options[:topology] = nil
    opts.on('-t', '--topology ARG', 'Topology of network') do |top|
      options[:topology] = top
    end
  end

  optparse.parse!
  return options
end

# Perform error checks on the parameters of the script and options
#
def check_for_errors(options)
  # Check that user is root.
  if Process.uid != 0
    puts("xlxc-net.rb must be run as root.")
    exit
  end

  name = options[:name]
  if name == nil
    puts("Specify name for container using -n or --name.")
    exit
  end

  size = options[:size]
  if size <= 0
    puts("The size of the network must be greater than zero.")
    exit
  end

  if size > 65534
    puts("The size of the network must be less than 65535.")
    exit
  end

  # Check that topology is valid.
  topology = options[:topology]
  if topology != "star" and topology != "connected"
    puts("Must indicate topology with either \"star\" or \"connected\".")
    exit
  end

  # Check that there are no conflicts with the container name.
  if !options[:delete]
    for i in 0..(size - 1)
      if File.exists?(File.join(XLXC::LXC, name + i.to_s()))
        puts("Container #{name + i.to_s()} already exists.")
        exit
      end
    end

    # We will use the naming scheme for the bridge, so make sure
    # there are no conflicts there.
    if !Dir.exists?(XLXC_BRIDGE::BRIDGES)
      `mkdir -p #{XLXC_BRIDGE::BRIDGES}`
    end

    if topology == "connected"
      if Dir.entries(XLXC_BRIDGE::BRIDGES).include?(name + "br") ||
         Dir.entries(XLXC_BRIDGE::INTERFACES).include?(name + "br")
        puts("Bridge #{name + "br"} is already in use, so this\n" \
             "naming scheme cannot be used.")
        exit
      end
    else
      for i in 0..(size - 1)
        if Dir.entries(XLXC_BRIDGE::BRIDGES).include?(name + i.to_s() + "br") ||
           Dir.entries(XLXC_BRIDGE::INTERFACES).include?(name + i.to_s() + "br")
          puts("Bridge #{name + i.to_s() + "br"} is already in use, so this\n" \
               "naming scheme cannot be used.")
          exit
        end
      end
    end
  end

  iface = options[:iface]
  if !options[:delete] and iface == nil
    puts("Specify host's gateway interface using -i or --iface.")
    exit
  end
end

# Creates a connected network of Linux XIA containrs, where each
# container is on the same Ethernet bridge.
#
def create_connected_network(name, size, iface)
  bridge = name + "br"
  cidr_str = XLXC_BRIDGE.get_free_cidr_block(size).to_s()
  `ruby xlxc-bridge.rb -b #{bridge} --add --iface #{iface} --cidr #{cidr_str}`
  for i in 0..(size - 1)
    `ruby xlxc-create.rb -n #{name + i.to_s()} -b #{bridge}`
  end
end

# Creates a star network of Linux XIA containers, where each
# container is on a separate Ethernet bridge.
#
def create_star_network(name, size, iface)
  for i in 0..(size - 1)
    bridge = name + i.to_s() + "br"
    cidr_str = XLXC_BRIDGE.get_free_cidr_block(size).to_s()
    `ruby xlxc-bridge.rb -b #{bridge} --add --iface #{iface} --cidr #{cidr_str}`
    `ruby xlxc-create.rb -n #{name + i.to_s()} -b #{bridge}`
  end
end

# Deletes a connected network of Linux XIA containrs, where each
# container is on the same Ethernet bridge.
#
def delete_connected_network(name, size)
  bridge = name + "br"
  for i in 0..(size - 1)
    `ruby xlxc-destroy.rb -n #{name + i.to_s()}`
  end
  `ruby xlxc-bridge.rb -b #{bridge} --del`
end

# Deletes a star network of Linux XIA containers, where each
# container is on a separate Ethernet bridge.
#
def delete_star_network(name, size)
  for i in 0..(size - 1)
    bridge = name + i.to_s() + "br"
    `ruby xlxc-destroy.rb -n #{name + i.to_s()}`
    `ruby xlxc-bridge.rb -b #{bridge} --del`
  end
end

if __FILE__ == $PROGRAM_NAME
  options = parse_opts()
  check_for_errors(options)
  name = options[:name]
  iface = options[:iface]
  size = options[:size]
  topology = options[:topology]
  to_delete = options[:delete]
  if !to_delete
    if topology == "connected"
      create_connected_network(name, size, iface)
    elsif topology == "star"
      create_star_network(name, size, iface)
    else
      raise("No option chosen.")
    end
  elsif
    if topology == "connected"
      delete_connected_network(name, size)
    elsif topology == "star"
      delete_star_network(name, size)
    else
      raise("No option chosen.")
    end
  end
end