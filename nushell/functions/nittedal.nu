# Nittedal train departures using Nushell
export def main [numberOfDepartures?: int, startTime?: string] {
    let num_departures = ($numberOfDepartures | default 5)
    
    let start_time = if ($startTime == null) {
        date now | format date "%Y-%m-%dT%H:%M%z"
    } else {
        let parts = ($startTime | split row ":")
        if ($parts | length) == 2 {
            let hour = ($parts | get 0)
            let minute = ($parts | get 1)
            date now | format date $"(%Y-%m-%d)T($hour):($minute)%z"
        } else {
            date now | format date "%Y-%m-%dT%H:%M%z"
        }
    }
    
    let graphql_query = "
query GetDepartures($stopPlace: String!, $lines: [ID!]!, $timeRange: Int = 86400, $numberOfDepartures: Int = 5, $startTime: DateTime) {
  stopPlace(id: $stopPlace) {
    estimatedCalls(timeRange: $timeRange, numberOfDepartures: $numberOfDepartures, startTime: $startTime, whiteListed: {
            lines: $lines,
    }) {
      expectedDepartureTime
      situations {
        summary {
          language
          value
        }
      }
      serviceJourney {
        journeyPattern {
          quays  {
            name
          }
        }
        line {
          publicCode
        }
      }
      destinationDisplay {
        frontText
      }

      quay {
        publicCode
        stopPlace {
            name
            description
        }
      }
    }
  }
}
    "
    
    let variables = {
        stopPlace: "NSR:StopPlace:59872",
        lines: ["VYG:Line:RE30", "VYG:Line:R31"],
        numberOfDepartures: $num_departures,
        startTime: $start_time
    }
    
    let request_body = {
        query: $graphql_query,
        variables: $variables
    }
    
    let raw_response = (http post 
        --content-type application/json
        --headers {
            "ET-Client-Name": "jonas-laptop-cli"
        }
        https://api.entur.io/journey-planner/v3/graphql
        $request_body)
    
    # Process the GraphQL response
    let data = ($raw_response
    | get data.stopPlace.estimatedCalls
    | where { |call| 
        $call.serviceJourney.journeyPattern.quays 
        | any { |quay| $quay.name == "Nittedal stasjon" }
    }
    | select -o expectedDepartureTime destinationDisplay.frontText quay.publicCode serviceJourney.line.publicCode quay.stopPlace.name quay.stopPlace.description situations.0.summary.0.value
    | rename -c {
        expectedDepartureTime: time,
        destinationDisplay.frontText: destination,
        quay.publicCode: quay,
        serviceJourney.line.publicCode: line,
        quay.stopPlace.name: stop_name,
        quay.stopPlace.description: stop_desc,
        situations.0.summary.0.value: situation
    }
    | update time {
      $in | into datetime | format date '%H:%M'
    } |
    | sort-by time)

  let empty_columns = (["stop_desc", "situation"] | where { |columnName|
    $data | get $columnName | compact  --empty | is-empty
  })

  $data | reject ...$empty_columns

}
