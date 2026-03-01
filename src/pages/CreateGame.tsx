import styles from '../styles/CreateGame.module.scss';

import { useNavigate } from 'react-router';

import { Flex, Button, Input, Slider, Switch } from 'antd';
import {
    EyeOutlined,
    ArrowLeftOutlined,
    CrownOutlined
} from '@ant-design/icons';


const CreateGame = () => {
    const navigate = useNavigate();

    const goToHome = () => {
        navigate('/');
    }

    return (
        <Flex className = { styles.container } vertical>
            <Flex align = 'center' justify = 'space-between'>
                <Button
                    onClick = { goToHome }
                    icon = { <ArrowLeftOutlined /> }
                    shape = 'circle'>
                </Button>

                <h1>Create New Game</h1>
            </Flex>

            <Flex vertical>
                <h3>THE ALIAS</h3>

                <Input placeholder = 'Enter a sneaky name...'></Input>
            </Flex>

            <Flex vertical>
                <h3>CROWDSIZE</h3>

                <Flex justify = 'space-between' align = 'center'>
                    <h2>4-12 Players</h2>

                    <span>8</span>
                </Flex>

                <Slider></Slider>

                <p>More players mean more chaos!</p>
            </Flex>

            <Flex vertical>
                <h3>SECURITY LEVEL</h3>

                <Flex justify = 'space-around' align = 'center'>
                    <EyeOutlined />

                    <Flex vertical>
                        <h3>Public Lobby</h3>
                        <p>Strangers can join the fun</p>
                    </Flex>

                    <Switch></Switch>
                </Flex>
            </Flex>

            <Flex vertical>
                <h3>VIBE CHECK</h3>

                <Flex justify = 'space-around' align = 'center'>
                    <Button icon = { <CrownOutlined /> }>Classic</Button>
                    <Button icon = { <CrownOutlined /> }>Hardcore</Button>
                </Flex>
            </Flex>

            <Button icon = { <CrownOutlined /> }>START SHENANIGANS</Button>
        </Flex>
    );
}

export default CreateGame;